module UnicornHorn

  class SelfPipeDaemon
    extend Configurer
    config :logger do Logger.new(STDERR) end

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

    def initialize
      SELF_PIPE.replace(IO.pipe)
      SELF_PIPE.each { |io| io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) }
    end

    def ploop
      Utils.proc_name 'master'
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

end
