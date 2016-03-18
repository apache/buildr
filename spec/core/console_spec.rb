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

describe Buildr::Console do

  describe 'console_dimensions' do

    it 'should return a value' do
      expect(Buildr::Console.console_dimensions).not_to be_nil if $stdout.isatty # have to ask again as stdout may be redirected.
    end if $stdout.isatty && !ENV["TRAVIS"] && !Buildr::Util.win_os?
  end

  describe 'color' do

    describe 'when use_color is true' do
      before do
        Buildr::Console.use_color = true
      end

      it 'should emit red code when asked' do
        expect(Buildr::Console.color('message', :red)).to eql("\e[31mmessage\e[0m")
      end

      it 'should emit green code when asked' do
        expect(Buildr::Console.color('message', :green)).to eql("\e[32mmessage\e[0m")
      end

      it 'should emit blue code when asked' do
        expect(Buildr::Console.color('message', :blue)).to eql("\e[34mmessage\e[0m")
      end
    end if $stdout.isatty && !Buildr::Util.win_os?

    describe ' use_color is false' do
      before do
        Buildr::Console.use_color = false
      end

      it 'should not emit red code when asked' do
        expect(Buildr::Console.color('message', :red)).to eql("message")
      end

      it 'should not emit green code when asked' do
        expect(Buildr::Console.color('message', :green)).to eql("message")
      end

      it 'should not emit blue code when asked' do
        expect(Buildr::Console.color('message', :blue)).to eql("message")
      end
    end
  end
end
