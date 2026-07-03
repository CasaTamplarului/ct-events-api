# frozen_string_literal: true

class PushNotification < ApplicationRecord
  DIRECTUS_URL = ENV.fetch('DIRECTUS_URL', 'https://adminctevents.chiciudean.family')

  belongs_to :event, optional: true
  belongs_to :created_by, class_name: 'User'

  validates :translations, presence: true
  validate  :ro_translation_present

  def translation_for(language)
    lang = language.to_s[0..1].downcase
    translations[lang] || translations['ro']
  end

  def image_url
    return nil if directus_file_id.blank?

    # Downscaled transform: originals can be huge (10MB+), while iOS caps
    # notification attachments at 10MB and gives the service extension ~30s.
    "#{DIRECTUS_URL}/assets/#{directus_file_id}?width=1200&quality=80&format=jpg"
  end

  private

    def ro_translation_present
      ro = translations&.dig('ro')
      errors.add(:translations, 'must include a Romanian (ro) translation') and return unless ro

      errors.add(:translations, 'ro translation must have a title') unless ro['title'].present?
      errors.add(:translations, 'ro translation must have a body')  unless ro['body'].present?
    end
end
