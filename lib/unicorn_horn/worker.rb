module UnicornHorn

  class Worker
    extend Configurer
    config :idle_timeout do 60; end
    config :logger       do Logger.new(STDERR); end

    attr_reader :name, :wpid

    def initialize handler
      @name    = handler.respond_to?(:name) ? handler.name : handler.inspect
      @handler = handler
    end

    def launch!
      @tmp = Utils.tmpio
      @wpid = fork do

        # the prep work
        Utils.proc_name "worker[#{name}]"
        AFTER_FORK.each{ |x| x.call }
        @tmp.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
        [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } }
        alive = @tmp
        m = 0
        @handler = @handler.new if @handler.respond_to?(:new)
        logger.info "worker=#{name} ready"

        # the actual loop
        while Process.ppid && alive
          alive.chmod(m = 0 == m ? 1 : 0)
          @handler.call
        end

      end
    end

    def kill_if_idle
      return unless @tmp and @wpid
      stat = @tmp.stat
      stat.mode == 0100600 and return
      (diff = (Time.now - stat.ctime)) <= idle_timeout and return
      logger.error "worker=#{name} PID:#{@wpid} timeout " \
                   "(#{diff}s > #{idle_timeout}s), killing"
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
      status.success? ? logger.info(m) : logger.error(m)
    end
  end

end
