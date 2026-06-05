# frozen_string_literal: true

module Api
  module V1
    class OrdersController < ActionController::API
      PERMITTED_ATTENDEE_FIELDS = %w[first_name last_name email_address phone_number dietary_preference allergies
                                     church_name city age].freeze

      before_action :set_locale
      before_action :set_current_user

      def create
        items = params[:items]
        return render json: { error: t('orders.errors.items_blank') }, status: :bad_request if items.blank?

        resolved = resolve_items(items)
        return if performed?

        check_capacity(resolved)
        return if performed?

        order = persist_order(resolved)
        SendgridService.send_booking_confirmation(order: order, language: params[:languages_code])
        render json: {
          order_reference: order.order_reference,
          attendees: order.attendees.map { |a| { id: a.id, qr_code: "#{order.order_reference}-#{a.id}" } }
        }, status: :created
      rescue StandardError
        render json: { error: t('orders.errors.internal_error') }, status: :internal_server_error
      end

      private

        def set_current_user
          token = request.headers['Authorization']&.split&.last
          return if token.blank?

          user_id = JwtService.decode(token)
          @current_user = User.active.find_by(id: user_id)
        rescue JWT::DecodeError
          nil
        end

        def resolve_items(items)
          items.each_with_object([]) do |item, result|
            event = Event.find_by(slug: item[:event_slug])
            unless event
              render json: { error: t('orders.errors.unknown_event', slug: item[:event_slug]) }, status: :bad_request
              break
            end

            ticket = event.tickets
                          .joins(:tickets_translations)
                          .where(tickets_translations: { name: item[:ticket_name],
                                                         languages_code: params[:languages_code] })
                          .first
            unless ticket
              render json: { error: t('orders.errors.unknown_ticket', name: item[:ticket_name]) }, status: :bad_request
              break
            end

            if ticket.for_leaders && !%w[leader admin volunteer].include?(@current_user&.role)
              render json: { error: t('orders.errors.leader_ticket_required') }, status: :forbidden
              break
            end

            attrs     = attendee_attrs(item[:attendee])
            uploads   = parse_template_doc_uploads(item[:attendee])
            responses = parse_boolean_field_responses(item[:attendee])

            break unless template_doc_uploads_valid?(event: event, attendee_attrs: attrs, uploads: uploads)
            break unless boolean_field_responses_valid?(event: event, responses: responses)

            result << { event: event, ticket: ticket, attendee_attrs: attrs,
                        template_doc_uploads: uploads, boolean_field_responses: responses }
          end
        end

        def check_capacity(resolved)
          resolved.group_by { |i| i[:event] }.each do |event, items_for_event|
            next unless event.max_number_of_people

            if event.attendees.count + items_for_event.size > event.max_number_of_people
              render json: { error: t('orders.errors.fully_booked') }, status: :conflict
              break
            end
          end
        end

        def persist_order(resolved)
          order = nil
          ActiveRecord::Base.transaction do
            order = Order.create!(user: @current_user)
            resolved.each do |item|
              email = item[:attendee_attrs][:email_address]
              linked_user = email.present? ? User.active.find_by('LOWER(email) = LOWER(?)', email) : nil
              attendee = order.attendees.create!(
                event: item[:event],
                ticket: item[:ticket],
                user: linked_user,
                **item[:attendee_attrs]
              )

              item[:template_doc_uploads].each do |upload|
                AttendeeTemplateDocUpload.create!(
                  attendee: attendee,
                  event_template_doc_id: upload[:event_template_doc_id],
                  directus_files_id: upload[:directus_files_id]
                )
              end

              item[:boolean_field_responses].each do |response|
                AttendeeBooleanFieldResponse.create!(
                  attendee: attendee,
                  event_boolean_field_id: response[:event_boolean_field_id],
                  value: response[:value]
                )
              end
            end
          end
          order
        end

        def parse_template_doc_uploads(raw_attendee)
          return [] if raw_attendee.blank?

          Array(raw_attendee[:template_doc_uploads]).map do |u|
            {
              event_template_doc_id: u[:event_template_doc_id].to_i,
              directus_files_id: u[:directus_files_id].to_s
            }
          end
        end

        def parse_boolean_field_responses(raw_attendee)
          return [] if raw_attendee.blank?

          Array(raw_attendee[:boolean_field_responses]).map do |r|
            {
              event_boolean_field_id: r[:event_boolean_field_id].to_i,
              value: r[:value]
            }
          end
        end

        def template_doc_uploads_valid?(event:, attendee_attrs:, uploads:)
          return false unless uploads_belong_to_event?(event, uploads)

          missing = missing_required_doc_labels(event, attendee_attrs, uploads)
          if missing.any?
            render json: { error: t('orders.errors.missing_required_docs', docs: missing.join(', ')) },
                   status: :bad_request
            return false
          end

          true
        end

        def uploads_belong_to_event?(event, uploads)
          event_doc_ids = event.event_template_docs.map(&:id)
          uploads.each do |upload|
            next if event_doc_ids.include?(upload[:event_template_doc_id])

            render json: { error: t('orders.errors.invalid_template_doc') }, status: :bad_request
            return false
          end
          true
        end

        def missing_required_doc_labels(event, attendee_attrs, uploads)
          uploaded_ids = uploads.pluck(:event_template_doc_id)
          attendee_age = attendee_attrs[:age]&.to_i

          event.event_template_docs.filter_map do |doc|
            next unless required_upload_missing?(doc, attendee_age, uploaded_ids)

            doc.label_for(params[:languages_code]) || doc.id.to_s
          end
        end

        def required_upload_missing?(doc, attendee_age, uploaded_ids)
          doc.required && doc_applies_to_age?(doc, attendee_age) && uploaded_ids.exclude?(doc.id)
        end

        def doc_applies_to_age?(doc, attendee_age)
          return true if doc.age_from.nil? && doc.age_to.nil?
          return false if attendee_age.nil?

          (doc.age_from.nil? || attendee_age >= doc.age_from) &&
            (doc.age_to.nil? || attendee_age <= doc.age_to)
        end

        def boolean_field_responses_valid?(event:, responses:)
          return false unless boolean_fields_belong_to_event?(event, responses)

          missing = missing_required_boolean_field_labels(event, responses)
          if missing.any?
            render json: { error: t('orders.errors.missing_required_boolean_fields', fields: missing.join(', ')) },
                   status: :bad_request
            return false
          end

          true
        end

        def boolean_fields_belong_to_event?(event, responses)
          event_field_ids = event.event_boolean_fields.map(&:id)
          responses.each do |response|
            next if event_field_ids.include?(response[:event_boolean_field_id])

            render json: { error: t('orders.errors.invalid_boolean_field') }, status: :bad_request
            return false
          end
          true
        end

        def missing_required_boolean_field_labels(event, responses)
          responded_ids = responses.pluck(:event_boolean_field_id)

          event.event_boolean_fields.filter_map do |field|
            next unless field.required
            next if responded_ids.include?(field.id)

            field.label_for(params[:languages_code]) || field.id.to_s
          end
        end

        def attendee_attrs(raw)
          raw.to_unsafe_h.slice(*PERMITTED_ATTENDEE_FIELDS).symbolize_keys
        end

        def set_locale
          lang = params[:languages_code].to_s.split('-').first.to_sym
          I18n.locale = I18n.available_locales.include?(lang) ? lang : I18n.default_locale
        end

        def t(key, **)
          I18n.t(key, **)
        end
    end
  end
end
