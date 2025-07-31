task :run do
	File.readlines('.env', chomp: true).each do |line|
		key, value = line.split '='
		ENV[key] = value
	end
	load 'main.rb'
end

task default: :run
