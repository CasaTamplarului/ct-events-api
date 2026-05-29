# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendgridService do
  describe '.send_password_reset' do
    let(:romanian_user) { build(:user, first_name: 'Ion', language: 'ro-RO', email: 'ion@example.com') }
    let(:english_user) { build(:user, first_name: 'John', language: 'en-US', email: 'john@example.com') }
    let(:reset_url) { 'https://app.example.com/reset-password?token=abc123' }

    before do
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
        .to_return(status: 202, body: '', headers: {})
    end

    it 'posts to the SendGrid mail/send endpoint' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
    end

    it 'sends with the correct template ID' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req| JSON.parse(req.body)['template_id'] == 'd-952a77f57d9f410597cfa1cf84260cef' }
    end

    it 'sets is_romanian to true for a Romanian user' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['is_romanian'] == true
        }
    end

    it 'sets is_romanian to false for a non-Romanian user' do
      SendgridService.send_password_reset(user: english_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['is_romanian'] == false
        }
    end

    it 'sends first_name and reset_url in dynamic template data' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['first_name'] == 'Ion' && data['reset_url'] == reset_url
        }
    end

    it 'includes the current year as a string in dynamic template data' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['year'] == Time.current.year.to_s
        }
    end
  end
end
