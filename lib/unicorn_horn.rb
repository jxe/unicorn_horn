require 'fcntl'
require 'tmpdir'

module UnicornHorn
  ORIG_ZERO = $0
  ARGVS = ARGV.join(' ')

  class Worker
    attr_accessor :name, :logger, :idle_timeout
    attr_reader :wpid
    attr_writer :master

    def initialize name, idle_timeout = 60, &blk
      @name         = name
      @idle_timeout = idle_timeout
      @blk          = blk
    end

    def launch!
      @tmp = tmpio
      @wpid = fork do
        $0 = "#{ORIG_ZERO} worker[#{name}] #{ARGVS}"
        @master.forget; @master = nil
        @tmp.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
        [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } }
        alive = @tmp
        m = 0
        logger.info "worker=#{name} ready"
        @blk.call(proc{
          if Process.ppid && alive
            alive.chmod(m = 0 == m ? 1 : 0) or true
          end
        })
      end
    end

    def tmpio
      fp = File.open("#{Dir::tmpdir}/#{rand}",
                 File::RDWR|File::CREAT|File::EXCL, 0600)
      File.unlink(fp.path)
      fp.binmode
      fp.sync = true
      fp
    rescue Errno::EEXIST
      retry
    end

    def kill_if_idle
      return unless @tmp and @wpid
      stat = @tmp.stat
      stat.mode == 0100600 and return
      @idle_timeout ||= 60
      (diff = (Time.now - stat.ctime)) <= @idle_timeout and return
      @logger.error "worker=#{name} PID:#{@wpid} timeout " \
                   "(#{diff}s > #{@idle_timeout}s), killing"
      kill(:KILL)
    end

    def kill(signal)
      return unless @wpid
      Process.kill(signal, @wpid)
      rescue Errno::ESRCH
        @wpid = nil
        @tmp.close rescue nil
    end

    def reap(status)
      @wpid = nil
      @tmp.close rescue nil
      m = "reaped #{status.inspect} worker=#{name}"
      status.success? ? @logger.info(m) : @logger.error(m)
    end
  end


  class SelfPipeDaemon
    attr_accessor :logger

    SELF_PIPE = []
    SIG_QUEUE = []

    def psleep(sec)
      IO.select([ SELF_PIPE[0] ], nil, nil, sec) or return
      SELF_PIPE[0].read_nonblock(16*1024, "")
      rescue Errno::EAGAIN, Errno::EINTR
    end

    def pwake
      SELF_PIPE[1].write_nonblock('.') # wakeup master process from select
      rescue Errno::EAGAIN, Errno::EINTR
    end

    def register *signals
      @signals = signals
      signals.each { |sig| trap(sig){ |sig_nr| SIG_QUEUE << sig; pwake } }
    end

    def initialize options = {}
      SELF_PIPE.replace(IO.pipe)
      SELF_PIPE.each { |io| io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) }
      options.each_pair{ |k,v| send("#{k}=", v) }
      yield self if block_given?
      self
    end

    def ploop
      $0 = "#{ORIG_ZERO} master #{ARGVS}"
      logger.info "master process ready"

      begin
        yield SIG_QUEUE.shift
      rescue => e
        logger.error "Unhandled master loop exception #{e.inspect}."
        logger.error e.backtrace.join("\n")
      end while true

      logger.info "master complete"
    end

    def forget
      @signals.each { |sig| trap(sig, nil) }
      SIG_QUEUE.clear
      SELF_PIPE.each { |io| io.close rescue nil }
    end
  end



  class Monitor < SelfPipeDaemon
    attr_accessor :workers, :kill_timeout

    def start
      workers.each{ |w| w.master = self; w.logger = logger }
      register :QUIT, :INT, :TERM, :CHLD
      workers.each(&:launch!)

      ploop do |signal|
        reap
        case signal
        when nil
          workers.each(&:kill_if_idle)
          workers.each{ |w| w.wpid or w.launch! }
          psleep 1
        when :CHLD;       next
        when :QUIT;       raze(:QUIT); break
        when :TERM, :INT; raze(:TERM); break
        end
      end
    end

    def forget
      super
      workers.clear
    end


    private

    def reap
      begin
        wpid, status = Process.waitpid2(-1, Process::WNOHANG)
        wpid or return
        next unless worker = workers.detect{ |w| w.wpid == wpid }
        worker.reap(status)
      rescue Errno::ECHILD
        break
      end while true
    end

    def raze(sig)
      limit = Time.now + (@kill_timeout ||= 60)
      until workers.empty? || Time.now > limit
        workers.each{ |w| w.kill(sig) }
        sleep(0.1)
        reap
      end
      workers.each{ |w| w.kill(:KILL) }
    end
  end
end
