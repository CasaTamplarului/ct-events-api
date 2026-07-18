# frozen_string_literal: true

class Event < ApplicationRecord
  has_many :attendees, dependent: :destroy
  has_many :events_translations, dependent: :destroy, inverse_of: :event
  has_many :tickets, -> { order(:sort) }, dependent: :destroy, inverse_of: :event
  has_many :event_attendee_fields, -> { order(:sort) }, dependent: :destroy, inverse_of: :event
  has_many :event_gallery_items, lambda {
    order(:sort)
  }, class_name: 'EventGallery', dependent: :destroy, inverse_of: :event
  has_many :event_speakers,      -> { order(:sort) }, dependent: :destroy, inverse_of: :event
  has_many :event_template_docs, -> { order(:sort) }, dependent: :destroy, inverse_of: :event
  has_many :event_boolean_fields,       -> { order(:sort) }, dependent: :destroy, inverse_of: :event
  has_many :event_description_sections, -> { order(:sort) }, dependent: :destroy, inverse_of: :event
  has_many :qa_sessions, dependent: :destroy
  has_many :event_teams, dependent: :destroy

  # Enums
  enum :status, { draft: 0, live: 1, cancelled: 2, deleted: 3 }

  # Scopes

  scope :public_only, -> { where(is_private: false) }
  scope :upcoming, -> { public_only.where(end_date: Time.zone.now..).where(status: 'live') }
  scope :past, -> { public_only.where(end_date: ...Time.zone.now).where(status: 'live') }
  scope :hero, lambda {
    public_only.where(hero: true, status: 'live')
               .where('end_date > ?', Time.zone.now)
               .order(start_date: :asc)
               .limit(1)
  }

  scope :by_filter, lambda { |filter|
    base = public_only.where(status: 'live')
    case filter.to_s
    when 'upcoming' then base.where(end_date: Time.zone.now..)
    when 'past'     then base.where(end_date: ...Time.zone.now)
    else                 base
    end
  }

  scope :by_keyword, lambda { |search, lang|
    return all if search.blank?

    joins(:events_translations)
      .where(events_translations: { languages_code: lang })
      .where(
        'events_translations.name ILIKE :q OR events_translations.tag_line ILIKE :q',
        q: "%#{sanitize_sql_like(search)}%"
      )
  }

  scope :by_year, lambda { |year|
    return all if year.blank?

    where('EXTRACT(YEAR FROM start_date) = ?', year.to_i)
  }

  scope :by_pricing, lambda { |pricing|
    return all if pricing.blank? || pricing.to_s == 'both'

    case pricing.to_s
    when 'free'
      left_joins(:tickets)
        .group('events.id')
        .having('MIN(tickets.price) IS NULL OR MIN(tickets.price) = 0')
    when 'paid'
      left_joins(:tickets)
        .group('events.id')
        .having('MIN(tickets.price) > 0')
    else
      all
    end
  }

  scope :sorted_for, lambda { |filter|
    case filter.to_s
    when 'upcoming' then order(start_date: :asc)
    else                 order(start_date: :desc)
    end
  }

  def translations(language_code)
    events_translations.find_by(languages_code: language_code)
  end

  def past?
    end_date < Time.zone.now
  end

  def fully_booked?
    return false if max_number_of_people.nil?

    attendees.count >= max_number_of_people
  end

  def starts_from
    tickets.where(for_leaders: false).minimum(:price)
  end
end
