# frozen_string_literal: true

module Api
  module V1
    class BookingTokenController < ActionController::API
      def show
        order = Order.find_by(booking_token: params[:token])
        return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

        lang = params[:lang].presence || 'ro-RO'

        attendees = order.attendees.includes(
          { ticket: %i[tickets_translations ticket_meal_slots] },
          { event: [:events_translations, { event_template_docs: :event_template_doc_translations }] },
          { attendee_boolean_field_responses: { event_boolean_field: :event_boolean_field_translations } }
        ).to_a

        return render json: { error: I18n.t('errors.not_found') }, status: :not_found if attendees.empty?

        render json: serialise_order(order, attendees, lang)
      end

      private

        def serialise_order(order, attendees, lang)
          event = attendees.first.event
          {
            order_reference: order.order_reference,
            payment_status: order.payment_status(attendees),
            total_price: attendees.sum { |a| a.ticket&.price || 0 },
            event: serialise_event(event, lang, attendees),
            attendees: attendees.map { |a| serialise_attendee(a, lang) }
          }
        end

        def serialise_event(event, lang, attendees)
          name = event.events_translations.find { |t| t.languages_code == lang }&.name ||
                 event.events_translations.find { |t| t.languages_code == 'ro-RO' }&.name
          {
            name: name,
            slug: event.slug,
            start_date: event.start_date,
            end_date: event.end_date,
            location_name: event.location_name,
            address: event.address,
            template_docs: serialise_template_docs(event.event_template_docs, lang, attendees)
          }
        end

        def serialise_template_docs(docs, lang, attendees) # rubocop:disable Metrics/CyclomaticComplexity
          ages = attendees.map(&:age)
          docs.select { |doc| doc_applies_to_any_attendee?(doc, ages) }
              .map do |doc|
                label = doc.event_template_doc_translations.find { |t| t.languages_code == lang }&.label ||
                        doc.event_template_doc_translations.find { |t| t.languages_code == 'ro-RO' }&.label
                {
                  id: doc.id,
                  label: label,
                  url: ApplicationSerializer.asset_url(doc.directus_files_id),
                  required: doc.required,
                  upload_enabled: doc.upload_enabled
                }
              end
        end

        def doc_applies_to_any_attendee?(doc, ages) # rubocop:disable Metrics/CyclomaticComplexity
          return true if doc.age_from.nil? && doc.age_to.nil?

          ages.any? do |age|
            next false if age.nil?

            (doc.age_from.nil? || age >= doc.age_from) &&
              (doc.age_to.nil? || age <= doc.age_to)
          end
        end

        def serialise_attendee(attendee, lang) # rubocop:disable Metrics/CyclomaticComplexity
          translation = ticket_translation_for(attendee, lang)
          {
            id: attendee.id,
            qr_code: attendee.qr_code,
            first_name: attendee.first_name,
            last_name: attendee.last_name,
            phone_number: attendee.phone_number,
            city: attendee.city,
            church_name: attendee.church_name,
            payment_status: attendee.payment_status,
            ticket_name: translation&.name,
            ticket_description: translation&.description,
            ticket_price: attendee.ticket&.price,
            valid_from: attendee.ticket&.valid_from,
            valid_to: attendee.ticket&.valid_to,
            food_included: attendee.ticket&.food_included,
            dietary_preference: attendee.dietary_preference,
            allergies: attendee.allergies,
            age: attendee.age,
            meal_slots: (attendee.ticket&.ticket_meal_slots || [])
                        .sort_by { |s| [s.occurs_on, s.sort || 0] }
                        .map { |s| { meal_type: s.meal_type, occurs_on: s.occurs_on } },
            boolean_field_responses: attendee.attendee_boolean_field_responses
                                     .map { |r| serialise_boolean_response(r, lang) }
          }
        end

        def serialise_boolean_response(response, lang)
          field = response.event_boolean_field
          t = field.event_boolean_field_translations.find { |tr| tr.languages_code == lang } ||
              field.event_boolean_field_translations.find { |tr| tr.languages_code == 'ro-RO' }
          {
            event_boolean_field_id: response.event_boolean_field_id,
            label: t&.label,
            value: response.value,
            true_label: t&.true_label,
            false_label: t&.false_label
          }
        end

        def ticket_translation_for(attendee, lang)
          translations = attendee.ticket&.tickets_translations
          return nil if translations.nil?

          translations.find { |t| t.languages_code == lang } ||
            translations.find { |t| t.languages_code == 'ro-RO' }
        end
    end
  end
end
