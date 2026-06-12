# frozen_string_literal: true

class HeroEventSerializer < ApplicationSerializer
  attributes :start_date, :end_date

  attribute :name do |object|
    object.translations(params[:languages_code]).name
  end

  attribute :tag_line do |object|
    object.translations(params[:languages_code]).tag_line
  end

  attribute :description do |object|
    object.translations(params[:languages_code]).description
  end

  attribute :description_sections do |object|
    sections = object.event_description_sections.includes(:event_description_section_translations)
    sections.map do |s|
      { label: s.label_for(params[:languages_code]),
        content: s.content_for(params[:languages_code]) }
    end
  end

  attribute :fully_booked, &:fully_booked?
  attribute :starts_from, &:starts_from

  attribute :tickets do |object|
    return nil unless object.tickets

    TicketSerializer.new(object.tickets, params: { languages_code: params[:languages_code] })
  end

  attribute :slug, &:slug
  attributes :address, :location_name, :embed_url

  attribute :hero_image do |object|
    ApplicationSerializer.asset_url(object.hero_image)
  end

  attribute :hero_image_type do |object|
    ApplicationSerializer.asset_type(object.hero_image)
  end

  attribute :hero_portrait do |object|
    ApplicationSerializer.asset_url(object.hero_portrait)
  end

  attribute :hero_portrait_type do |object|
    ApplicationSerializer.asset_type(object.hero_portrait)
  end
end
