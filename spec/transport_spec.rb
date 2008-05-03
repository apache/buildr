# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.


require File.join(File.dirname(__FILE__), 'spec_helpers')


describe URI, '#download' do
  before do
    write @source = 'source', @content = 'Just a file'
    @uri = URI("file://#{File.expand_path(@source)}")
    @target = 'target'
  end

  it 'should download file if found' do
    @uri.download @target
    file(@target).should contain(@content)
  end

  it 'should fail if file not found' do
    lambda { (@uri + 'missing').download @target }.should raise_error(URI::NotFoundError)
    file(@target).should_not exist
  end

  it 'should work the same way from static method with URI' do
    URI.download @uri, @target
    file(@target).should contain(@content)
  end

  it 'should work the same way from static method with String' do
    URI.download @uri.to_s, @target
    file(@target).should contain(@content)
  end

  it 'should download to a task' do
    @uri.download file(@target)
    file(@target).should contain(@content)
  end

  it 'should download to a file' do
    File.open(@target, 'w') { |file| @uri.download file }
    file(@target).should contain(@content)
  end
end


describe URI, '#upload' do
  before do
    write @source = 'source', @content = 'Just a file'
    @target = 'target'
    @uri = URI("file://#{File.expand_path(@target)}")
  end

  it 'should upload file if found' do
    @uri.upload @source
    file(@target).should contain(@content)
  end

  it 'should fail if file not found' do
    lambda { @uri.upload @source.ext('missing') }.should raise_error(URI::NotFoundError)
    file(@target).should_not exist
  end

  it 'should work the same way from static method with URI' do
    URI.upload @uri, @source
    file(@target).should contain(@content)
  end

  it 'should work the same way from static method with String' do
    URI.upload @uri.to_s, @source
    file(@target).should contain(@content)
  end

  it 'should upload from a task' do
    @uri.upload file(@source)
    file(@target).should contain(@content)
  end

  it 'should create MD5 hash' do
    @uri.upload file(@source)
    file(@target.ext('.md5')).should contain(Digest::MD5.hexdigest(@content))
  end

  it 'should create SHA1 hash' do
    @uri.upload file(@source)
    file(@target.ext('.sha1')).should contain(Digest::SHA1.hexdigest(@content))
  end

  it 'should upload an entire directory' do
    mkpath 'dir' ; write 'dir/test', 'in directory'
    mkpath 'dir/nested' ; write 'dir/nested/test', 'in nested directory'
    @uri.upload 'dir'
    file(@target).should contain('test', 'nested/test')
    file(@target + '/test').should contain('in directory')
    file(@target + '/nested/test').should contain('in nested directory')
  end
end


describe URI::FILE do
  it 'should complain about file:' do
    lambda { URI('file:') }.should raise_error(URI::InvalidURIError)
  end

  it 'should accept file:something as file:///something' do
    URI('file:something').should eql(URI('file:///something'))
  end

  it 'should accept file:/ as file:///' do
    URI('file:/').should eql(URI('file:///'))
  end

  it 'should accept file:/something as file:///something' do
    URI('file:/something').should eql(URI('file:///something'))
  end

  it 'should complain about file://' do
    lambda { URI('file://').should eql(URI('file:///')) }.should raise_error(URI::InvalidURIError)
  end

  it 'should accept file://something as file://something/' do
    URI('file://something').should eql(URI('file://something/'))
  end

  it 'should accept file:///something' do
    URI('file:///something').should be_kind_of(URI::FILE)
    URI('file:///something').to_s.should eql('file:///something')
    URI('file:///something').path.should eql('/something')
  end

  it 'should treat host as path when host name is a Windows drive' do
    URI('file://c:/something').should eql(URI('file:///c:/something'))
  end
end


describe URI::FILE, '#read' do
  before do
    @filename = 'readme'
    @uri = URI("file:///#{File.expand_path(@filename)}")
    @content = 'Readme. Please!'
    write 'readme', @content
  end

  it 'should not complain about excessive options' do
    @uri.read :proxy=>[], :lovely=>true
  end

  it 'should read the file' do
    @uri.read.should eql(@content)
  end

  it 'should read the file and yield to block' do
    @uri.read { |content| content.should eql(@content) }
  end

  it 'should raise NotFoundError if file doesn\'t exist' do
    lambda { (@uri + 'notme').read }.should raise_error(URI::NotFoundError)
  end

  it 'should raise NotFoundError if file is actually a directory' do
    mkpath 'dir'
    lambda { (@uri + 'dir').read }.should raise_error(URI::NotFoundError)
  end
end


describe URI::FILE, '#write' do
  before do
    @filename = 'readme'
    @uri = URI("file:///#{File.expand_path(@filename)}")
    @content = 'Readme. Please!'
  end

  it 'should not complain about excessive options' do
    @uri.write @content, :proxy=>[], :lovely=>true
  end

  it 'should write the file from a string' do
    @uri.write @content
    read(@filename).should eql(@content)
  end

  it 'should write the file from a reader' do
    reader = Object.new
    class << reader
      def read(bytes) ; @array.pop ; end
    end
    reader.instance_variable_set :@array, [@content]
    @uri.write reader
    read(@filename).should eql(@content)
  end

  it 'should write the file from a block' do
    array = [@content]
    @uri.write { array.pop }
    read(@filename).should eql(@content)
  end

  it 'should not create file if read fails' do
    @uri.write { fail } rescue nil
    file(@filename).should_not exist
  end
end


describe URI::HTTP, '#read' do
  before do
    @proxy = 'http://john:smith@myproxy:8080'
    @domain = 'domain'
    @host_domain = "host.#{@domain}"
    @uri = URI("http://#{@host_domain}")
    @no_proxy_args = [@host_domain, 80]
    @proxy_args = @no_proxy_args + ['myproxy', 8080, 'john', 'smith']
    @http = mock('http')
    @http.stub!(:request).and_yield(Net::HTTPNotModified.new(nil, nil, nil))
  end

  it 'should not use proxy unless proxy is set' do
    Net::HTTP.should_receive(:new).with(*@no_proxy_args).and_return(@http)
    @uri.read
  end

  it 'should use proxy from environment variable HTTP_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    Net::HTTP.should_receive(:new).with(*@proxy_args).and_return(@http)
    @uri.read
  end

  it 'should not use proxy for hosts from environment variable NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = @host_domain
    Net::HTTP.should_receive(:new).with(*@no_proxy_args).and_return(@http)
    @uri.read
  end

  it 'should use proxy for hosts other than those specified by NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = 'whatever'
    Net::HTTP.should_receive(:new).with(*@proxy_args).and_return(@http)
    @uri.read
  end

  it 'should support comma separated list in environment variable NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = 'optimus,prime'
    Net::HTTP.should_receive(:new).with('optimus', 80).and_return(@http)
    URI('http://optimus').read
    Net::HTTP.should_receive(:new).with('prime', 80).and_return(@http)
    URI('http://prime').read
    Net::HTTP.should_receive(:new).with('bumblebee', *@proxy_args[1..-1]).and_return(@http)
    URI('http://bumblebee').read
  end

  it 'should support glob pattern in NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = "*.#{@domain}"
    Net::HTTP.should_receive(:new).once.with(*@no_proxy_args).and_return(@http)
    @uri.read
  end

  it 'should support specific port in NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = "#{@host_domain}:80"
    Net::HTTP.should_receive(:new).with(*@no_proxy_args).and_return(@http)
    @uri.read
    ENV['NO_PROXY'] = "#{@host_domain}:800"
    Net::HTTP.should_receive(:new).with(*@proxy_args).and_return(@http)
    @uri.read
  end

  it 'should not die if content size is zero' do
    ok = Net::HTTPOK.new(nil, nil, nil)
    ok.stub!(:read_body)
    @http.stub!(:request).and_yield(ok)
    Net::HTTP.should_receive(:new).and_return(@http)
    $stdout.should_receive(:isatty).and_return(false)
    @uri.read :progress=>true
  end

  it 'should use HTTP Basic authentication' do
    Net::HTTP.should_receive(:new).and_return(@http)
    request = mock('request')
    Net::HTTP::Get.should_receive(:new).and_return(request)
    request.should_receive(:basic_auth).with('john', 'secret')
    URI("http://john:secret@#{@host_domain}").read
  end
end


describe URI::HTTP, '#write' do
end


describe URI::SFTP, '#write' do
  before do
    @uri = URI('sftp://john:secret@localhost/path/readme')
    @content = 'Readme. Please!'

    @ssh_session = mock('Net::SSH::Session')
    @sftp_session = mock('Net::SFTP::Session')
    @file_factory = mock('Net::SFTP::Operations::FileFactory')
    Net::SSH.stub!(:start).with('localhost', 'john', :password=>'secret', :port=>22) do
      Net::SFTP::Session.should_receive(:new).with(@ssh_session).and_yield(@sftp_session).and_return(@sftp_session)
      @sftp_session.should_receive(:connect!).and_return(@sftp_session)
      @sftp_session.should_receive(:loop)
      @sftp_session.stub!(:mkdir)
      @sftp_session.should_receive(:file).with.and_return(@file_factory)
      @file_factory.stub!(:open)
      @ssh_session.should_receive(:close)
      @ssh_session
    end
  end

  it 'should open connection to SFTP server' do
    @uri.write @content
  end

  it 'should create path recursively on SFTP server' do
    @sftp_session.should_receive(:mkdir).ordered.with('', {})
    @sftp_session.should_receive(:mkdir).ordered.with('/path', {})
    @uri.write @content
  end

  it 'should only create paths that don\'t exist' do
    @sftp_session.should_receive(:realpath).any_number_of_times
    @sftp_session.should_not_receive(:mkdir)
    @uri.write @content
  end

  it 'should open file for writing' do
    @file_factory.should_receive(:open).with('/path/readme', 'w')
    @uri.write @content
  end

  it 'should write contents to file' do
    file = mock('Net::SFTP::Operations::File')
    file.should_receive(:write).with(@content)
    @file_factory.should_receive(:open).with('/path/readme', 'w').and_yield(file)
    @uri.write @content
  end

end


describe URI::SFTP, '#read' do
  before do
    @uri = URI('sftp://john:secret@localhost/path/readme')
    @content = 'Readme. Please!'

    @ssh_session = mock('Net::SSH::Session')
    @sftp_session = mock('Net::SFTP::Session')
    @file_factory = mock('Net::SFTP::Operations::FileFactory')
    Net::SSH.stub!(:start).with('localhost', 'john', :password=>'secret', :port=>22) do
      Net::SFTP::Session.should_receive(:new).with(@ssh_session).and_yield(@sftp_session).and_return(@sftp_session)
      @sftp_session.should_receive(:connect!).and_return(@sftp_session)
      @sftp_session.should_receive(:loop)
      @sftp_session.should_receive(:file).with.and_return(@file_factory)
      @file_factory.stub!(:open)
      @ssh_session.should_receive(:close)
      @ssh_session
    end
  end

  it 'should open connection to SFTP server' do
    @uri.read
  end

  it 'should open file for reading' do
    @file_factory.should_receive(:open).with('/path/readme', 'r')
    @uri.read
  end

  it 'should read contents of file and return it' do
    file = mock('Net::SFTP::Operations::File')
    file.should_receive(:read).with(an_instance_of(Numeric)).once.and_return(@content, nil)
    @file_factory.should_receive(:open).with('/path/readme', 'r').and_yield(file)
    @uri.read.should eql(@content)
  end

  it 'should read contents of file and pass it to block' do
    file = mock('Net::SFTP::Operations::File')
    file.should_receive(:read).with(an_instance_of(Numeric)).once.and_return(@content, nil)
    @file_factory.should_receive(:open).with('/path/readme', 'r').and_yield(file)
    content = ''
    @uri.read do |chunk|
      content << chunk
    end
    content.should eql(@content)
  end
end
