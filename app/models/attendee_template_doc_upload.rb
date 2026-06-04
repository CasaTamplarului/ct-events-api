# frozen_string_literal: true

class AttendeeTemplateDocUpload < ApplicationRecord
  belongs_to :attendee
  belongs_to :event_template_doc

  validates :directus_files_id, presence: true
  validates :event_template_doc_id, uniqueness: { scope: :attendee_id }
end
