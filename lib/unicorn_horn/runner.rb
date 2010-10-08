module UnicornHorn
  class Runner < SelfPipeDaemon

    def initialize handlers
      super()
      @workers = handlers.map{ |handler| Worker.new handler }
    end

    def start
      register :QUIT, :INT, :TERM, :CHLD, :HUP
      AFTER_FORK << proc{ @workers.clear; forget }
      @workers.each{ |w| w.launch! }

      ploop do |signal|
        reap
        case signal
        when nil
          @workers.each{ |w| w.kill_if_idle }
          @workers.each{ |w| w.wpid or w.launch! }
          psleep 1
        when :CHLD;       next
        when :HUP;        raze(:QUIT,  5);
        when :QUIT;       raze(:QUIT, 60); break
        when :TERM, :INT; raze(:TERM,  5); break
        end
      end
    end


    private

    def reap
      begin
        wpid, status = Process.waitpid2(-1, Process::WNOHANG)
        wpid or return
        next unless worker = @workers.detect{ |w| w.wpid == wpid }
        worker.reap(status)
      rescue Errno::ECHILD
        break
      end while true
    end

    def raze(sig, timeframe)
      limit = Time.now + timeframe
      until @workers.empty? || Time.now > limit
        @workers.each{ |w| w.kill(sig) }
        sleep(0.1)
        reap
      end
      @workers.each{ |w| w.kill(:KILL) }
    end

  end
end
