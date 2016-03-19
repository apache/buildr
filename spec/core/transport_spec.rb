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


require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helpers'))


describe URI, '#download' do
  before do
    write @source = File.expand_path('source'), @content = 'A file to download'
    @uri = URI(URI.escape("file://#{@source}"))
    @target = File.expand_path('target')
    rm_f @target
  end

  it 'should download file if found' do
    @uri.download @target
    expect(file(@target)).to contain(@content)
  end

  it 'should fail if file not found' do
    expect { (@uri + 'missing').download @target }.to raise_error(URI::NotFoundError)
    expect(file(@target)).not_to exist
  end

  it 'should work the same way from static method with URI' do
    URI.download @uri, @target
    expect(file(@target)).to contain(@content)
  end

  it 'should work the same way from static method with String' do
    URI.download @uri.to_s, @target
    expect(file(@target)).to contain(@content)
  end

  it 'should download to a task' do
    @uri.download file(@target)
    expect(file(@target)).to contain(@content)
  end

  it 'should download to a file' do
    File.open(@target, 'w') { |file| @uri.download file }
    expect(file(@target)).to contain(@content)
  end
end


describe URI, '#upload' do
  before do
    write @source = 'source', @content = 'Just a file'
    @target = File.expand_path('target')
    rm_rf @target
    @uri = URI(URI.escape("file://#{@target}"))
  end

  it 'should preserve file permissions if uploading to a file' do
    File.chmod(0666, @source)
    s = File.stat(@source).mode
    @uri.upload @source
    expect(File.stat(@target).mode).to eql(s)
  end

  it 'should upload file if found' do
    @uri.upload @source
    expect(file(@target)).to contain(@content)
  end

  it 'should fail if file not found' do
    expect { @uri.upload @source.ext('missing') }.to raise_error(URI::NotFoundError)
    expect(file(@target)).not_to exist
  end

  it 'should work the same way from static method with URI' do
    URI.upload @uri, @source
    expect(file(@target)).to contain(@content)
  end

  it 'should work the same way from static method with String' do
    URI.upload @uri.to_s, @source
    expect(file(@target)).to contain(@content)
  end

  it 'should upload from a task' do
    @uri.upload file(@source)
    expect(file(@target)).to contain(@content)
  end

  it 'should create MD5 hash' do
    @uri.upload file(@source)
    expect(file(@target.ext('.md5'))).to contain(Digest::MD5.hexdigest(@content))
  end

  it 'should create SHA1 hash' do
    @uri.upload file(@source)
    expect(file(@target.ext('.sha1'))).to contain(Digest::SHA1.hexdigest(@content))
  end

  it 'should upload an entire directory' do
    mkpath 'dir' ; write 'dir/test', 'in directory'
    mkpath 'dir/nested' ; write 'dir/nested/test', 'in nested directory'
    @uri.upload 'dir'
    expect(file(@target)).to contain('test', 'nested/test')
    expect(file(@target + '/test')).to contain('in directory')
    expect(file(@target + '/nested/test')).to contain('in nested directory')
  end
end


describe URI::FILE do

  it 'should accept file:something as file:///something' do
    expect(URI('file:something')).to eql(URI('file:///something'))
  end

  it 'should accept file:/ as file:///' do
    expect(URI('file:/')).to eql(URI('file:///'))
  end

  it 'should accept file:/something as file:///something' do
    expect(URI('file:/something')).to eql(URI('file:///something'))
  end

  it 'should accept file://something as file://something/' do
    expect(URI('file://something')).to eql(URI('file://something/'))
  end

  it 'should accept file:///something' do
    expect(URI('file:///something')).to be_kind_of(URI::FILE)
    expect(URI('file:///something').to_s).to eql('file:///something')
    expect(URI('file:///something').path).to eql('/something')
  end

  it 'should treat host as path when host name is a Windows drive' do
    expect(URI('file://c:/something')).to eql(URI('file:///c:/something'))
  end
end


describe URI::FILE, '#read' do
  before do
    @filename = 'readme'
    @uri = URI(URI.escape("file:///#{File.expand_path(@filename)}"))
    @content = 'Readme. Please!'
    write 'readme', @content
  end

  it 'should not complain about excessive options' do
    @uri.read :proxy=>[], :lovely=>true
  end

  it 'should read the file' do
    expect(@uri.read).to eql(@content)
  end

  it 'should read the file and yield to block' do
    @uri.read { |content| expect(content).to eql(@content) }
  end

  it 'should raise NotFoundError if file doesn\'t exist' do
    expect { (@uri + 'notme').read }.to raise_error(URI::NotFoundError)
  end

  it 'should raise NotFoundError if file is actually a directory' do
    mkpath 'dir'
    expect { (@uri + 'dir').read }.to raise_error(URI::NotFoundError)
  end
end


describe URI::FILE, '#write' do
  before do
    @filename = 'readme'
    @uri = URI(URI.escape("file:///#{File.expand_path(@filename)}"))
    @content = 'Readme. Please!'
  end

  it 'should not complain about excessive options' do
    @uri.write @content, :proxy=>[], :lovely=>true
  end

  it 'should write the file from a string' do
    @uri.write @content
    expect(read(@filename)).to eql(@content)
  end

  it 'should write the file from a reader' do
    reader = Object.new
    class << reader
      def read(bytes) ; @array.pop ; end
    end
    reader.instance_variable_set :@array, [@content]
    @uri.write reader
    expect(read(@filename)).to eql(@content)
  end

  it 'should write the file from a block' do
    array = [@content]
    @uri.write { array.pop }
    expect(read(@filename)).to eql(@content)
  end

  it 'should not create file if read fails' do
    @uri.write { fail } rescue nil
    expect(file(@filename)).not_to exist
  end
end


def default_http_headers
  {"Cache-Control" => "no-cache", "User-Agent" => "Buildr-#{Buildr::VERSION}"}
end

describe URI::HTTP, '#read' do
  before do
    @proxy = 'http://john:smith@myproxy:8080'
    @domain = 'domain'
    @host_domain = "host.#{@domain}"
    @path = "/foo/bar/baz"
    @query = "?query"
    @uri = URI("http://#{@host_domain}#{@path}#{@query}")
    @no_proxy_args = [@host_domain, 80]
    @proxy_args = @no_proxy_args + ['myproxy', 8080, 'john', 'smith']
    @http = double('http')
    allow(@http).to receive(:request).and_yield(Net::HTTPNotModified.new(nil, nil, nil))
  end

  it 'should not use proxy unless proxy is set' do
    expect(Net::HTTP).to receive(:new).with(*@no_proxy_args).and_return(@http)
    @uri.read
  end

  it 'should use HTTPS if applicable' do
    expect(Net::HTTP).to receive(:new).with(@host_domain, 443).and_return(@http)
    expect(@http).to receive(:use_ssl=).with(true)
    URI(@uri.to_s.sub(/http/, 'https')).read
  end

  it 'should use proxy from environment variable HTTP_PROXY when using http' do
    ENV['HTTP_PROXY'] = @proxy
    expect(Net::HTTP).to receive(:new).with(*@proxy_args).and_return(@http)
    @uri.read
  end

  it 'should use proxy from environment variable HTTPS_PROXY when using https' do
    ENV['HTTPS_PROXY'] = @proxy
    expect(Net::HTTP).to receive(:new).with(@host_domain, 443, 'myproxy', 8080, 'john', 'smith').and_return(@http)
    expect(@http).to receive(:use_ssl=).with(true)
    URI(@uri.to_s.sub(/http/, 'https')).read
  end

  it 'should not use proxy for hosts from environment variable NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = @host_domain
    expect(Net::HTTP).to receive(:new).with(*@no_proxy_args).and_return(@http)
    @uri.read
  end

  it 'should use proxy for hosts other than those specified by NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = 'whatever'
    expect(Net::HTTP).to receive(:new).with(*@proxy_args).and_return(@http)
    @uri.read
  end

  it 'should support comma separated list in environment variable NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = 'optimus,prime'
    expect(Net::HTTP).to receive(:new).with('optimus', 80).and_return(@http)
    URI('http://optimus').read
    expect(Net::HTTP).to receive(:new).with('prime', 80).and_return(@http)
    URI('http://prime').read
    expect(Net::HTTP).to receive(:new).with('bumblebee', *@proxy_args[1..-1]).and_return(@http)
    URI('http://bumblebee').read
  end

  it 'should support glob pattern in NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = "*.#{@domain}"
    expect(Net::HTTP).to receive(:new).once.with(*@no_proxy_args).and_return(@http)
    @uri.read
  end

  it 'should support specific port in NO_PROXY' do
    ENV['HTTP_PROXY'] = @proxy
    ENV['NO_PROXY'] = "#{@host_domain}:80"
    expect(Net::HTTP).to receive(:new).with(*@no_proxy_args).and_return(@http)
    @uri.read
    ENV['NO_PROXY'] = "#{@host_domain}:800"
    expect(Net::HTTP).to receive(:new).with(*@proxy_args).and_return(@http)
    @uri.read
  end

  it 'should not die if content size is zero' do
    ok = Net::HTTPOK.new(nil, nil, nil)
    allow(ok).to receive(:read_body)
    allow(@http).to receive(:request).and_yield(ok)
    expect(Net::HTTP).to receive(:new).and_return(@http)
    expect($stdout).to receive(:isatty).and_return(false)
    @uri.read :progress=>true
  end

  it 'should use HTTP Basic authentication' do
    expect(Net::HTTP).to receive(:new).and_return(@http)
    request = double('request')
    expect(Net::HTTP::Get).to receive(:new).and_return(request)
    expect(request).to receive(:basic_auth).with('john', 'secret')
    URI("http://john:secret@#{@host_domain}").read
  end

  it 'should preseve authentication information during a redirect' do
    expect(Net::HTTP).to receive(:new).twice.and_return(@http)

    # The first request will produce a redirect
    redirect = Net::HTTPRedirection.new(nil, nil, nil)
    redirect['Location'] = "http://#{@host_domain}/asdf"

    request1 = double('request1')
    expect(Net::HTTP::Get).to receive(:new).once.with('/', default_http_headers).and_return(request1)
    expect(request1).to receive(:basic_auth).with('john', 'secret')
    expect(@http).to receive(:request).with(request1).and_yield(redirect)

    # The second request will be ok
    ok = Net::HTTPOK.new(nil, nil, nil)
    allow(ok).to receive(:read_body)

    request2 = double('request2')
    expect(Net::HTTP::Get).to receive(:new).once.with("/asdf", default_http_headers).and_return(request2)
    expect(request2).to receive(:basic_auth).with('john', 'secret')
    expect(@http).to receive(:request).with(request2).and_yield(ok)

    URI("http://john:secret@#{@host_domain}").read
  end

  it 'should include the query part when performing HTTP GET' do
    # should this test be generalized or shared with any other URI subtypes?
    allow(Net::HTTP).to receive(:new).and_return(@http)
    expect(Net::HTTP::Get).to receive(:new).with(/#{Regexp.escape(@query)}$/, default_http_headers)
    @uri.read
  end

end


describe URI::HTTP, '#write' do
  before do
    @content = 'Readme. Please!'
    @uri = URI('http://john:secret@host.domain/foo/bar/baz.jar')
    @http = double('Net::HTTP')
    allow(@http).to receive(:request).and_return(Net::HTTPOK.new(nil, nil, nil))
    allow(Net::HTTP).to receive(:new).and_return(@http)
  end

  it 'should open connection to HTTP server' do
    expect(Net::HTTP).to receive(:new).with('host.domain', 80).and_return(@http)
    @uri.write @content
  end

  it 'should use HTTP basic authentication' do
    expect(@http).to receive(:request) do |request|
      expect(request['authorization']).to eq('Basic ' + ['john:secret'].pack('m').delete("\r\n"))
      Net::HTTPOK.new(nil, nil, nil)
    end
    @uri.write @content
  end

  it 'should use HTTPS if applicable' do
    expect(Net::HTTP).to receive(:new).with('host.domain', 443).and_return(@http)
    expect(@http).to receive(:use_ssl=).with(true)
    URI(@uri.to_s.sub(/http/, 'https')).write @content
  end

  it 'should upload file with PUT request' do
    expect(@http).to receive(:request) do |request|
      expect(request).to be_kind_of(Net::HTTP::Put)
      Net::HTTPOK.new(nil, nil, nil)
    end
    @uri.write @content
  end

  it 'should set Content-Length header' do
    expect(@http).to receive(:request) do |request|
      expect(request.content_length).to eq(@content.size)
      Net::HTTPOK.new(nil, nil, nil)
    end
    @uri.write @content
  end

  it 'should set Content-MD5 header' do
    expect(@http).to receive(:request) do |request|
      expect(request['Content-MD5']).to eq(Digest::MD5.hexdigest(@content))
      Net::HTTPOK.new(nil, nil, nil)
    end
    @uri.write @content
  end

  it 'should send entire content' do
    expect(@http).to receive(:request) do |request|
      body_stream = request.body_stream
      expect(body_stream.read(1024)).to eq(@content)
      expect(body_stream.read(1024)).to be_nil
      Net::HTTPOK.new(nil, nil, nil)
    end
    @uri.write @content
  end

  it 'should fail on 4xx response' do
    expect(@http).to receive(:request).and_return(Net::HTTPBadRequest.new(nil, nil, nil))
    expect { @uri.write @content }.to raise_error(RuntimeError, /failed to upload/i)
  end

  it 'should fail on 5xx response' do
    expect(@http).to receive(:request).and_return(Net::HTTPServiceUnavailable.new(nil, nil, nil))
    expect { @uri.write @content }.to raise_error(RuntimeError, /failed to upload/i)
  end

end


describe URI::SFTP, '#read' do
  before do
    @uri = URI('sftp://john:secret@localhost/root/path/readme')
    @content = 'Readme. Please!'

    @ssh_session = double('Net::SSH::Session')
    @sftp_session = double('Net::SFTP::Session')
    @file_factory = double('Net::SFTP::Operations::FileFactory')
    allow(Net::SSH).to receive(:start).with('localhost', 'john', :password=>'secret', :port=>22).and_return(@ssh_session)
    expect(Net::SFTP::Session).to receive(:new).with(@ssh_session).and_yield(@sftp_session).and_return(@sftp_session)
    expect(@sftp_session).to receive(:connect!).and_return(@sftp_session)
    expect(@sftp_session).to receive(:loop)
    expect(@sftp_session).to receive(:file).and_return(@file_factory)
    allow(@file_factory).to receive(:open)
    expect(@ssh_session).to receive(:close)
  end

  it 'should open connection to SFTP server' do
    @uri.read
  end

  it 'should open file for reading' do
    expect(@file_factory).to receive(:open).with('/root/path/readme', 'r')
    @uri.read
  end

  it 'should read contents of file and return it' do
    file = double('Net::SFTP::Operations::File')
    expect(file).to receive(:read).with(URI::RW_CHUNK_SIZE).once.and_return(@content)
    expect(@file_factory).to receive(:open).with('/root/path/readme', 'r').and_yield(file)
    expect(@uri.read).to eql(@content)
  end

  it 'should read contents of file and pass it to block' do
    file = double('Net::SFTP::Operations::File')
    expect(file).to receive(:read).with(URI::RW_CHUNK_SIZE).once.and_return(@content)
    expect(@file_factory).to receive(:open).with('/root/path/readme', 'r').and_yield(file)
    content = ''
    @uri.read do |chunk|
      content << chunk
    end
    expect(content).to eql(@content)
  end
end


describe URI::SFTP, '#write' do
  before do
    @uri = URI('sftp://john:secret@localhost/root/path/readme')
    @content = 'Readme. Please!'

    @ssh_session = double('Net::SSH::Session')
    @sftp_session = double('Net::SFTP::Session')
    @file_factory = double('Net::SFTP::Operations::FileFactory')
    allow(Net::SSH).to receive(:start).with('localhost', 'john', :password=>'secret', :port=>22).and_return(@ssh_session)
    expect(Net::SFTP::Session).to receive(:new).with(@ssh_session).and_yield(@sftp_session).and_return(@sftp_session)
    expect(@sftp_session).to receive(:connect!).and_return(@sftp_session)
    expect(@sftp_session).to receive(:loop)
    allow(@sftp_session).to receive(:opendir!) { fail }
    allow(@sftp_session).to receive(:close)
    allow(@sftp_session).to receive(:mkdir!)
    expect(@sftp_session).to receive(:file).and_return(@file_factory)
    allow(@file_factory).to receive(:open)
    expect(@ssh_session).to receive(:close)
  end

  it 'should open connection to SFTP server' do
    @uri.write @content
  end

  it 'should check that path exists on server' do
    paths = ['/root', '/root/path']
    expect(@sftp_session).to receive(:opendir!).with(anything()).twice { |path| expect(paths.shift).to eq(path) }
    @uri.write @content
  end

  it 'should close all opened directories' do
    expect(@sftp_session).to receive(:opendir!).with(anything()).twice do |path|
      expect(@sftp_session).to receive(:close).with(handle = Object.new)
      handle
    end
    @uri.write @content
  end

  it 'should create missing paths on server' do
    expect(@sftp_session).to receive(:opendir!) { |path| fail unless path == '/root' }
    expect(@sftp_session).to receive(:mkdir!).once.with('/root/path', {})
    @uri.write @content
  end

  it 'should create missing directories recursively' do
    paths = ['/root', '/root/path']
    expect(@sftp_session).to receive(:mkdir!).with(anything(), {}).twice { |path, options| expect(paths.shift).to eq(path) }
    @uri.write @content
  end

  it 'should open file for writing' do
    expect(@file_factory).to receive(:open).with('/root/path/readme', 'w')
    @uri.write @content
  end

  it 'should write contents to file' do
    file = double('Net::SFTP::Operations::File')
    expect(file).to receive(:write).with(@content)
    expect(@file_factory).to receive(:open).with('/root/path/readme', 'w').and_yield(file)
    @uri.write @content
  end

end
