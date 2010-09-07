require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "unicorn_horn"
    gem.summary = %Q{An extraction of the process monitoring code from Unicorn}
    gem.email = "joe@citizenlogistics.com"
    gem.homepage = "http://github.com/jxe/unicorn_horn"
    gem.authors = ["Joe Edelman"]
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end


require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "unicorn_horn #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
