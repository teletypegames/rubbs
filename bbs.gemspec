Gem::Specification.new do |s|
  s.name        = 'bbs'
  s.version     = '0.1.0'
  s.summary     = 'Universal telnet BBS server library'
  s.author      = 'Zsolt Tasnadi'
  s.files       = Dir['lib/**/*.rb']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 3.0'
  s.add_dependency 'artii', '~> 2.1'
end
