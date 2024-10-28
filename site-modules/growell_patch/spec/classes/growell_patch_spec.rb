# frozen_string_literal: true

require 'spec_helper'

describe 'growell_patch' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      if os_facts[:kernel] == 'windows'
        let(:facts) do
          os_facts.merge(
            {
              'puppet_confdir' => 'C:/ProgramData/PuppetLabs/puppet/etc',
              'puppet_vardir'  => 'C:/ProgramData/PuppetLabs/puppet/cache',
            }
          )
        end
      else
        let(:facts) do
          os_facts.merge(
            {
              'puppet_confdir' => '/etc/puppetlabs/puppet',
              'puppet_vardir'  => '/opt/puppetlabs/puppet/cache',
            }
          )
        end
      end

      it { is_expected.to compile }
    end
  end
end
