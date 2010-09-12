require 'logger'
require 'fcntl'
require 'configurer'
require 'unicorn_horn/utils'
require 'unicorn_horn/self_pipe_daemon'
require 'unicorn_horn/worker'
require 'unicorn_horn/runner'

module UnicornHorn
  AFTER_FORK = []
end
