#require 'rake/testtask'
require 'rspec/core'
require 'rspec/core/rake_task'

namespace :hyhead do

  desc "Execute Continuous Integration build (docs, tests with coverage)"
  task :ci do
    Rake::Task["hyhead:doc"].invoke
    Rake::Task["hydra:jetty:config"].invoke
    
    require 'jettywrapper'
    jetty_params = {
      :jetty_home => File.expand_path(File.dirname(__FILE__) + '/../jetty'),
      :quiet => false,
      :jetty_port => 8983,
      :solr_home => File.expand_path(File.dirname(__FILE__) + '/../jetty/solr'),
      :fedora_home => File.expand_path(File.dirname(__FILE__) + '/../jetty/fedora/default'),
      :startup_wait => 30
      }

    # does this make jetty run in TEST environment???
    error = Jettywrapper.wrap(jetty_params) do
      ### This will make it slower, can't we just invoke the  hydra:fixtures:refresh task?
      system("rake hydra:fixtures:refresh environment=test")
      Rake::Task['hyhead:setup_test_app'].invoke
      Rake::Task['hyhead:test'].invoke
    end
    raise "test failures: #{error}" if error
  end

  
  desc "Easiest way to run rspec tests. Copies code to host plugins dir, loads fixtures, then runs specs - need to have jetty running."
  task :spec => "rspec:setup_and_run"
  
  namespace :rspec do
      
    desc "Run the hydra-head specs - need to have jetty running, test host set up and fixtures loaded."
    RSpec::Core::RakeTask.new(:run) do |t|
  #    t.spec_opts = ['--options', "/spec/spec.opts"]
      t.pattern = 'test_support/spec/**/*_spec.rb'
      t.rcov = true
      t.rcov_opts = lambda do
        IO.readlines("test_support/spec/rcov.opts").map {|l| l.chomp.split " "}.flatten
      end
    end
    
    desc "Sets up test host, loads fixtures, then runs specs - need to have jetty running."
    task :setup_and_run => ["hyhead:setup_test_app"] do
      system("rake hyhead:fixtures:refresh environment=test")
      Rake::Task["hyhead:rspec:run"].invoke
    end
        
  end

  
  # The following is a task named :doc which generates documentation using yard
  begin
    require 'yard'
    require 'yard/rake/yardoc_task'
    project_root = File.expand_path("#{File.dirname(__FILE__)}/../")
    doc_destination = File.join(project_root, 'doc')
    if !File.exists?(doc_destination) 
      FileUtils.mkdir_p(doc_destination)
    end

    YARD::Rake::YardocTask.new(:doc) do |yt|
      readme_filename = 'README.textile'
      textile_docs = []
      Dir[File.join(project_root, "*.textile")].each_with_index do |f, index| 
        unless f.include?("/#{readme_filename}") # Skip readme, which is already built by the --readme option
          textile_docs << '-'
          textile_docs << f
        end
      end
      yt.files   = Dir.glob(File.join(project_root, '*.rb')) + 
                   Dir.glob(File.join(project_root, 'app', '**', '*.rb')) + 
                   Dir.glob(File.join(project_root, 'lib', '**', '*.rb')) + 
                   textile_docs
      yt.options = ['--output-dir', doc_destination, '--readme', readme_filename]
    end
  rescue LoadError
    desc "Generate YARD Documentation"
    task :doc do
      abort "Please install the YARD gem to generate rdoc."
    end
  end
  
  #
  # Cucumber
  #
  
  
  # desc "Easieset way to run cucumber tests. Sets up test host, refreshes fixtures and runs cucumber tests"
  # task :cucumber => "cucumber:setup_and_run"
  task :cucumber => "cucumber:run"
  

  namespace :cucumber do
   
   desc "Run cucumber tests for hyhead - need to have jetty running, test host set up and fixtures loaded."
   task :run => :set_test_host_path do
     Dir.chdir(TEST_HOST_PATH)
     puts "Running cucumber features in test host app"
     puts %x[rake hyhead:cucumber]
     # puts %x[cucumber --color --tags ~@pending --tags ~@overwritten features]
     raise "Cucumber tests failed" unless $?.success?
     FileUtils.cd('../../')
   end
 
   # desc "Sets up test host, loads fixtures, then runs cucumber features - need to have jetty running."
   # task :setup_and_run => ["hyhead:setup_test_app", "hyhead:remove_features_from_host", "hyhead:copy_features_to_host"] do
   #   system("rake hydra:fixtures:refresh environment=test")
   #   Rake::Task["hyhead:cucumber:run"].invoke
   # end    
  end
   
# Not sure if these are necessary - MZ 09Jul2011 
  # desc "Copy current contents of the features directory into TEST_HOST_PATH/test_support/features"
  # task :copy_features_to_host => [:set_test_host_path] do
  #   features_dir = "#{TEST_HOST_PATH}/test_support/features"
  #   excluded = [".", ".."]
  #   FileUtils.mkdir_p(features_dir)
  #   puts "Copying features to #{features_dir}"
  #   # puts %x[ls -l test_support/features/mods_asset_search_result.feature]
  #   %x[cp -R test_support/features/* #{features_dir}]
  # end
  # 
  # desc "Remove TEST_HOST_PATH/test_support/features"
  # task :remove_features_from_host => [:set_test_host_path] do
  #   features_dir = "#{TEST_HOST_PATH}/test_support/features"
  #   puts "Emptying out #{features_dir}"
  #   %x[rm -rf #{features_dir}]
  # end
  
  
  #
  # Misc Tasks
  #
  
  desc "Creates a new test app and runs the cukes/specs from within it"
  task :clean_test_app => [:set_test_host_path] do
    puts "Cleaning out test app path"
    %x[rm -fr #{TEST_HOST_PATH}]
    FileUtils.mkdir_p(TEST_HOST_PATH)
    
    puts "Copying over .rvmrc file"
    FileUtils.cp("./test_support/etc/rvmrc",File.join(TEST_HOST_PATH,".rvmrc"))
    FileUtils.cd("tmp")
    system("source ./test_app/.rvmrc")
    
    puts "Installing rails, bundler and devise"
    %x[gem install --no-rdoc --no-ri 'rails']
    %x[gem install --no-rdoc --no-ri 'bundler']
    %x[gem install --no-rdoc --no-ri 'devise']
    
    puts "Generating new rails app"
    %x[rails new test_app]
    FileUtils.cd('test_app')

    puts "Copying Gemfile from test_support/etc"
    FileUtils.cp('../../test_support/etc/Gemfile','./Gemfile')

    puts "Creating local vendor/cache dir and copying gems from hyhead-rails3 gemset"
    FileUtils.cp_r(File.join('..','..','vendor','cache'), './vendor')
    
    puts "Copying fixtures into test app spec/fixtures directory"
    FileUtils.mkdir_p( File.join('.','test_support') )
    FileUtils.cp_r(File.join('..','..','test_support','fixtures'), File.join('.','test_support','fixtures'))
    
    puts "Executing bundle install --local"
    %x[bundle install --local]
    errors << 'Error running bundle install in test app' unless $?.success?

    puts "Installing cucumber in test app"
    %x[rails g cucumber:install]
    errors << 'Error installing cucumber in test app' unless $?.success?

    puts "generating default blacklight install"
    %x[rails generate blacklight --devise]
    errors << 'Error generating default blacklight install' unless $?.success?
    
    puts "generating default hydra-head install"
    %x[rails generate hydra:head -df]  # using -f to force overwriting of solr.yml
    errors << 'Error generating default hydra-head install' unless $?.success?

    puts "Running rake db:migrate"
    %x[rake db:migrate]
    %x[rake db:migrate RAILS_ENV=test]
    
    FileUtils.cd('../../')
    
    raise "Errors: #{errors.join("; ")}" unless errors.empty?

  end
  
  task :set_test_host_path do
    TEST_HOST_PATH = File.join(File.expand_path(File.dirname(__FILE__)),'..','tmp','test_app')
  end
  
  #
  # Test
  #

  desc "Run tests against test app"
  task :test => [:use_test_app]  do
    
    puts "Running rspec tests"
    %[bundle exec hyhead:rspec:rcov]
    
    puts "Running cucumber tests"
    %[bundle exec hyhead:cucumber:rcov]
  end
  
  desc "Make sure the test app is installed, then run the tasks from its root directory"
  task :use_test_app => [:set_test_host_path] do
    Rake::Task['hyhead:setup_test_app'].invoke unless File.exist?(TEST_HOST_PATH)
    FileUtils.cd(TEST_HOST_PATH)
  end
end
