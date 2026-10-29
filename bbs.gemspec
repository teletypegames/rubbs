Gem::Specification.new do |s|
  s.name        = 'bbs'
  s.version     = '0.20.1'
  s.summary     = 'Universal telnet BBS server library'
  s.license     = 'MIT'
  s.author      = 'Zsolt Tasnadi'
  s.files       = Dir['lib/**/*.rb']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 3.0'
  s.homepage    = 'https://wiki.teletypegames.org/engines/rubbs'
  s.metadata    = {
    'source_code_uri' => 'https://git.teletypegames.org/engines/rubbs',
    'documentation_uri' => 'https://wiki.teletypegames.org/rdoc/bbs/latest/'
  }
  s.add_dependency 'artii', '~> 2.1'
end
