# frozen_string_literal: true

class EventSerializer < ApplicationSerializer
  attributes :start_date, :end_date, :address, :location_name, :embed_url

  attribute :name do |object|
    object.translations(params[:languages_code]).name
  end

  attribute :tag_line do |object|
    object.translations(params[:languages_code]).tag_line
  end

  attribute :description do |object|
    object.translations(params[:languages_code]).description
  end

  attribute :fully_booked, &:fully_booked?
  attribute :starts_from do |object|
    object.past? ? nil : object.starts_from
  end

  attribute :tickets do |object|
    next nil if object.past? || object.tickets.empty?

    visible = object.tickets.reject do |t|
      t.hidden && params[:current_user]&.role != 'admin'
    end

    next nil if visible.empty?

    TicketSerializer.new(visible, params: { languages_code: params[:languages_code],
                                            current_user: params[:current_user] })
  end

  attribute :speakers do |object|
    next nil if object.event_speakers.empty?

    EventSpeakerSerializer.new(object.event_speakers, params: { languages_code: params[:languages_code] })
  end

  attribute :hero_image do |object|
    ApplicationSerializer.asset_url(object.hero_image)
  end

  attribute :hero_portrait do |object|
    ApplicationSerializer.asset_url(object.hero_portrait)
  end

  attribute :gallery do |object|
    object.event_gallery_items.map do |item|
      ApplicationSerializer.asset_url(item.directus_files_id)
    end
  end

  attribute :template_docs do |object|
    docs = object.event_template_docs.includes(:event_template_doc_translations)
    docs.map do |doc|
      { id: doc.id,
        label: doc.label_for(params[:languages_code]),
        url: ApplicationSerializer.asset_url(doc.directus_files_id),
        required: doc.required,
        upload_enabled: doc.upload_enabled,
        age_from: doc.age_from,
        age_to: doc.age_to }
    end
  end

  attribute :boolean_fields do |object|
    fields = object.event_boolean_fields.includes(:event_boolean_field_translations)
    fields.map do |f|
      {
        id: f.id,
        required: f.required,
        display_as: f.display_as,
        label: f.label_for(params[:languages_code]),
        true_label: f.true_label_for(params[:languages_code]),
        false_label: f.false_label_for(params[:languages_code])
      }
    end
  end

  attribute :description_sections do |object|
    sections = object.event_description_sections.includes(:event_description_section_translations)
    sections.map do |s|
      { label: s.label_for(params[:languages_code]),
        content: s.content_for(params[:languages_code]) }
    end
  end

  attribute :attendee_fields do |object|
    object.event_attendee_fields.map do |f|
      validation = if f.field_name == 'age'
                     min_max = { min: object.min_age, max: object.max_age }.compact
                     min_max[:allow_over_max] = true if object.max_age && object.allow_over_max_age
                     min_max.empty? ? nil : min_max
                   end
      { field: f.field_name, required: f.required, validation: validation }
    end
  end
end
