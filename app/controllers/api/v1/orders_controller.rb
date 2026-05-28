# frozen_string_literal: true

module Api
  module V1
    class OrdersController < ActionController::API
      PERMITTED_ATTENDEE_FIELDS = %w[first_name last_name email_address phone_number dietary_preference church_name city].freeze

      before_action :set_locale

      def create
        items = params[:items]
        return render json: { error: t('orders.errors.items_blank') }, status: :bad_request if items.blank?

        resolved = resolve_items(items)
        return if performed?

        check_capacity(resolved)
        return if performed?

        check_duplicate_registrations(resolved)
        return if performed?

        order = persist_order(resolved)

        render json: { order_reference: order.order_reference }, status: :created
      rescue StandardError
        render json: { error: t('orders.errors.internal_error') }, status: :internal_server_error
      end

      private

      def resolve_items(items)
        items.map do |item|
          event = Event.find_by(slug: item[:event_slug])
          unless event
            render json: { error: t('orders.errors.unknown_event', slug: item[:event_slug]) }, status: :bad_request
            return
          end

          ticket = event.tickets
                        .joins(:tickets_translations)
                        .where(tickets_translations: { name: item[:ticket_name], languages_code: params[:languages_code] })
                        .first
          unless ticket
            render json: { error: t('orders.errors.unknown_ticket', name: item[:ticket_name]) }, status: :bad_request
            return
          end

          { event: event, ticket: ticket, attendee_attrs: attendee_attrs(item[:attendee]) }
        end
      end

      def check_capacity(resolved)
        resolved.group_by { |i| i[:event] }.each do |event, items_for_event|
          next unless event.max_number_of_people

          if event.attendees.count + items_for_event.size > event.max_number_of_people
            render json: { error: t('orders.errors.fully_booked') }, status: :conflict
            return
          end
        end
      end

      def check_duplicate_registrations(resolved)
        resolved.each do |item|
          email = item[:attendee_attrs][:email_address]
          next if email.blank?

          if Attendee.exists?(event: item[:event], email_address: email)
            render json: { error: t('orders.errors.already_registered', email: email) }, status: :unprocessable_entity
            return
          end
        end
      end

      def persist_order(resolved)
        order = nil
        ActiveRecord::Base.transaction do
          order = Order.create!
          resolved.each do |item|
            order.attendees.create!(
              event: item[:event],
              ticket: item[:ticket],
              **item[:attendee_attrs]
            )
          end
        end
        order
      end

      def attendee_attrs(raw)
        raw.to_unsafe_h.slice(*PERMITTED_ATTENDEE_FIELDS).symbolize_keys
      end

      def set_locale
        lang = params[:languages_code].to_s.split('-').first.to_sym
        I18n.locale = I18n.available_locales.include?(lang) ? lang : I18n.default_locale
      end

      def t(key, **opts)
        I18n.t(key, **opts)
      end
    end
  end
end
