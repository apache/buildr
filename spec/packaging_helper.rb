shared_examples_for 'packaging' do
  it 'should create artifact of proper type' do
    packaging = @packaging
    package_type = @package_type || @packaging
    define 'foo', :version=>'1.0' do
      package(packaging).type.should eql(package_type) rescue exit!
    end
  end

  it 'should create file with proper extension' do
    packaging = @packaging
    package_type = @package_type || @packaging
    define 'foo', :version=>'1.0' do
      package(packaging).to_s.should match(/.#{package_type}$/)
    end
  end

  it 'should always return same task for the same package' do
    packaging = @packaging
    define 'foo', :version=>'1.0' do
      package(packaging)
      package(packaging, :id=>'other')
    end
    project('foo').packages.uniq.size.should eql(2)
  end

  it 'should complain if option not known' do
    packaging = @packaging
    define 'foo', :version=>'1.0' do
      lambda { package(packaging, :unknown_option=>true) }.should raise_error(ArgumentError, /no such option/)
    end
  end

  it 'should respond to with() and return self' do
    packaging = @packaging
    define 'foo', :version=>'1.0' do
      package(packaging).with({}).should be(package(packaging))
    end
  end

  it 'should respond to with() and complain if unknown option' do
    packaging = @packaging
    define 'foo', :version=>'1.0' do
      lambda {  package(packaging).with(:unknown_option=>true) }.should raise_error(ArgumentError, /does not support the option/)
    end
  end
end


