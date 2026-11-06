# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'rubbs'
  s.version     = '4.0.0'
  s.summary     = 'Universal telnet BBS server library'
  s.license     = 'MIT'
  s.author      = 'Zsolt Tasnadi'
  s.files       = Dir['lib/**/*.rb'] + %w[bin/art-preview bin/bbs-health]
  s.bindir      = 'bin'
  s.executables = %w[art-preview bbs-health]
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 3.2'
  s.homepage    = 'https://wiki.teletypegames.org/engines/rubbs'
  s.metadata    = {
    'source_code_uri'   => 'https://git.teletypegames.org/engines/rubbs',
    'documentation_uri' => 'https://wiki.teletypegames.org/rdoc/rubbs/latest/'
  }
  s.add_dependency 'artii', '~> 2.1'
  s.add_dependency 'csv', '~> 3.3'
  s.add_dependency 'rqrcode_core', '~> 2.1'
  s.add_dependency 'sequel', '~> 5.0'
  s.add_dependency 'sqlite3', '~> 2.1'
  s.add_dependency 'webrick', '~> 1.9'
end
