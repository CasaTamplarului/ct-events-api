# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AttendeeTemplateDocUpload, type: :model do
  subject(:upload) { build(:attendee_template_doc_upload) }

  it { is_expected.to belong_to(:attendee) }
  it { is_expected.to belong_to(:event_template_doc) }
  it { is_expected.to validate_presence_of(:directus_files_id) }
  it { is_expected.to validate_uniqueness_of(:event_template_doc_id).scoped_to(:attendee_id) }
end
