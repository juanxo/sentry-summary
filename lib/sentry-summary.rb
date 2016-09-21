current_dir = File.dirname(__FILE__)
Dir["#{current_dir}/**/*.rb"].each { |file| require_relative file }
