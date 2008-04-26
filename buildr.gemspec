Gem::Specification.new do |spec|
  spec.name           = 'buildr'
  spec.version        = '1.3.0'
  spec.author         = 'Apache Buildr'
  spec.email          = "#{spec.name}-user@incubator.apache.org"
  spec.homepage       = "http://incubator.apache.org/#{spec.name}/"
  spec.summary        = 'A build system that doesn\'t suck'

  spec.files          = FileList['lib/**/*', 'addon/**/*', 'README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER', 'KEYS',
                                 '*.gemspec', 'Rakefile', 'rakelib/**/*', 'spec/**/*', 'doc/**/*'].to_ary
  spec.require_paths  = ['lib', 'addon']
  spec.bindir         = 'bin'                               # Use these for applications.
  spec.executable     = 'buildr'

  spec.has_rdoc           = true
  spec.extra_rdoc_files   = ['README', 'CHANGELOG', 'LICENSE', 'NOTICE', 'DISCLAIMER']
  spec.rdoc_options       << '--title' << "Buildr -- #{spec.summary}" <<
                             '--main' << 'README' << '--line-numbers' << '--inline-source' << '-p' <<
                             '--webcvs' << 'http://svn.apache.org/repos/asf/incubator/#{spec.name}/trunk/'
  spec.rubyforge_project  = 'buildr'

  # Tested against these dependencies.
  spec.add_dependency 'rake',                 '~> 0.8'
  spec.add_dependency 'builder',              '~> 2.1'
  spec.add_dependency 'net-ssh',              '~> 1.1'
  spec.add_dependency 'net-sftp',             '~> 1.1'
  spec.add_dependency 'rubyzip',              '~> 0.9'
  spec.add_dependency 'highline',             '~> 1.4'
  spec.add_dependency 'Antwrap',              '~> 0.7'
  spec.add_dependency 'rspec',                '~> 1.1'
  spec.add_dependency 'xml-simple',           '~> 1.0'
  spec.add_dependency 'archive-tar-minitar',  '~> 0.5'
  spec.add_dependency 'rubyforge',            '~> 0.4'
  spec.add_dependency 'rjb', '~>1.1', '!=1.1.3' # 1.1.3 is missing Windows Gem.
end
