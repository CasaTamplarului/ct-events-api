# frozen_string_literal: true

class Event < ApplicationRecord
  has_many :attendees, dependent: :destroy
  has_many :events_translations, dependent: :destroy, inverse_of: :event
  has_many :tickets, dependent: :destroy
  has_many :event_attendee_fields, -> { order(:sort) }, dependent: :destroy, inverse_of: :event
  has_many :event_gallery_items, -> { order(:sort) }, class_name: "EventGallery", dependent: :destroy, inverse_of: :event
  has_many :event_speakers, -> { order(:sort) }, dependent: :destroy, inverse_of: :event

  # Enums
  enum :status, { draft: 0, live: 1, cancelled: 2, deleted: 3 }

  # Scopes

  scope :upcoming, -> { where(start_date: Time.zone.now..).where(status: 'live') }
  scope :past, -> { where(start_date: ...Time.zone.now).where(status: 'live') }
  scope :hero, lambda {
    where(hero: true)
      .where('start_date > ?', Time.zone.now)
      .order(start_date: :asc)
      .limit(1)
  }

  def translations(language_code)
    events_translations.find_by(languages_code: language_code)
  end

  def past?
    start_date < Time.zone.now
  end

  def fully_booked?
    return false if max_number_of_people.nil?

    attendees.count >= max_number_of_people
  end

  def starts_from
    tickets.minimum(:price)
  end
end
