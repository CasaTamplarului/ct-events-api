# frozen_string_literal: true

module Api
  module V1
    module Auth
      module Me
        class BookingsController < ActionController::API
          include Authenticatable
          include LocaleSetter

          before_action :authenticate_user!
          before_action :set_locale

          def upcoming
            orders = orders_for_user_scoped_to(
              where_clause: 'events.end_date > ?',
              sort: 'orders.created_at DESC'
            )
            render json: serialise_orders(orders)
          end

          def past
            orders = orders_for_user_scoped_to(
              where_clause: 'events.end_date <= ?',
              sort: 'orders.created_at DESC'
            )
            render json: serialise_orders(orders)
          end

          def check
            slugs = params[:slugs]
            if slugs.blank?
              render json: { error: I18n.t('auth.errors.slugs_required') },
                     status: :unprocessable_content
              return
            end

            slugs = slugs.first(50)
            result = slugs.index_with { { has_booking: false, order_reference: nil } }

            Attendee
              .joins(:event, :order)
              .where(user_id: current_user.id)
              .where(payment_status: %i[paid payment_pending])
              .where(events: { slug: slugs })
              .select('events.slug AS event_slug, orders.order_reference')
              .each do |row|
                next if result[row.event_slug][:has_booking]

                result[row.event_slug] = { has_booking: true, order_reference: row.order_reference }
              end

            render json: result
          end

          def cancel_order
            order = Order.find_by(order_reference: params[:order_reference])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

            user_attendees = order.attendees.where(user_id: current_user.id)
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found if user_attendees.empty?

            cancellable = user_attendees.where(payment_status: :payment_pending)
            if cancellable.empty?
              return render json: { error: I18n.t('bookings.errors.nothing_to_cancel') },
                            status: :unprocessable_content
            end

            reason      = params[:reason].presence
            reason_text = params[:reason_text].presence

            if reason && Attendee::CANCELLATION_REASONS.exclude?(reason)
              return render json: { error: 'Invalid cancellation reason' }, status: :unprocessable_content
            end

            first_cancelled_id = cancellable.pick(:id)

            # rubocop:disable Rails/SkipsModelValidations
            cancellable.update_all(
              payment_status: Attendee.payment_statuses['attendee_cancelled'],
              cancellation_reason: reason,
              cancellation_reason_text: reason_text
            )
            # rubocop:enable Rails/SkipsModelValidations

            SendCancellationAlertJob.perform_later(first_cancelled_id) if first_cancelled_id

            render json: serialise_order(order, attendees_for_response(order))
          end

          ATTENDEE_UPDATE_SCALAR_FIELDS = %w[first_name last_name phone_number dietary_preference
                                             church_name city age].freeze

          def update_attendee
            order = Order.find_by(order_reference: params[:order_reference])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

            attendee = order.attendees.find_by(id: params[:id])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

            unless attendee.user_id == current_user.id || order.user_id == current_user.id
              return render json: { error: I18n.t('errors.not_found') }, status: :not_found
            end

            if attendee.event.end_date <= Time.current
              return render json: { error: I18n.t('bookings.errors.event_already_past') },
                            status: :unprocessable_content
            end

            attrs = params.permit(*ATTENDEE_UPDATE_SCALAR_FIELDS, allergies: []).to_h.symbolize_keys
            unless attendee.update(attrs)
              return render json: { error: attendee.errors.full_messages.first },
                            status: :unprocessable_content
            end

            update_boolean_responses(attendee) if params[:boolean_field_responses].present?

            render json: serialise_order(order, attendees_for_response(order))
          end

          def cancel_attendee
            order = Order.find_by(order_reference: params[:order_reference])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

            attendee = order.attendees.find_by(id: params[:id], user_id: current_user.id)
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

            unless attendee.payment_pending?
              return render json: { error: I18n.t('bookings.errors.cannot_cancel') },
                            status: :unprocessable_content
            end

            reason      = params[:reason].presence
            reason_text = params[:reason_text].presence

            if reason && Attendee::CANCELLATION_REASONS.exclude?(reason)
              return render json: { error: 'Invalid cancellation reason' }, status: :unprocessable_content
            end

            attendee.update!(
              payment_status: :attendee_cancelled,
              cancellation_reason: reason,
              cancellation_reason_text: reason_text
            )

            SendCancellationAlertJob.perform_later(attendee.id)

            render json: serialise_order(order, attendees_for_response(order))
          end

          def wallet_google
            order = Order.find_by(order_reference: params[:order_reference])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

            base     = order.attendees.includes(:order, event: :events_translations)
            attendee = base.find_by(user_id: current_user.id)
            attendee ||= base.order(:id).first if order.user_id == current_user.id

            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

            lang = current_user.language || 'ro-RO'
            url  = GoogleWalletService.new(attendee: attendee, language: lang).save_url
            render json: { url: url }
          rescue GoogleWalletService::ApiError, StandardError => e
            Rails.logger.error("Google Wallet error for #{order&.order_reference}: #{e.class}: #{e.message}")
            render json: { error: 'Internal server error' }, status: :internal_server_error
          end

          def wallet_google_attendee
            order = Order.find_by(order_reference: params[:order_reference])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

            base     = order.attendees.includes(event: :events_translations)
            attendee = base.find_by(id: params[:id], user_id: current_user.id)
            attendee ||= base.find_by(id: params[:id]) if order.user_id == current_user.id

            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

            lang = current_user.language || 'ro-RO'
            url  = GoogleWalletService.new(attendee: attendee, language: lang).save_url
            render json: { url: url }
          rescue GoogleWalletService::ApiError, StandardError => e
            Rails.logger.error("Google Wallet error for attendee #{attendee&.id}: #{e.class}: #{e.message}")
            render json: { error: 'Internal server error' }, status: :internal_server_error
          end

          def wallet_apple
            order = Order.find_by(order_reference: params[:order_reference])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

            base     = order.attendees.includes(:order, event: :events_translations)
            attendee = base.find_by(user_id: current_user.id)
            attendee ||= base.order(:id).first if order.user_id == current_user.id

            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

            lang = current_user.language || 'ro-RO'
            data = AppleWalletService.new(attendee: attendee, language: lang).pass_data
            send_data data,
                      type: 'application/vnd.apple.pkpass',
                      filename: "ticket-#{order.order_reference}.pkpass",
                      disposition: 'inline'
          rescue AppleWalletService::PassGenerationError => e
            Rails.logger.error("Apple Wallet error for #{order.order_reference}: #{e.message}")
            render json: { error: 'Internal server error' }, status: :internal_server_error
          end

          def wallet_apple_attendee
            order = Order.find_by(order_reference: params[:order_reference])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

            base     = order.attendees.includes(event: :events_translations)
            attendee = base.find_by(id: params[:id], user_id: current_user.id)
            attendee ||= base.find_by(id: params[:id]) if order.user_id == current_user.id

            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

            lang = current_user.language || 'ro-RO'
            data = AppleWalletService.new(attendee: attendee, language: lang).pass_data
            send_data data,
                      type: 'application/vnd.apple.pkpass',
                      filename: "ticket-#{order.order_reference}.pkpass",
                      disposition: 'inline'
          rescue AppleWalletService::PassGenerationError => e
            Rails.logger.error("Apple Wallet error for attendee #{attendee.id}: #{e.message}")
            render json: { error: 'Internal server error' }, status: :internal_server_error
          end

          private

            def attendees_for_response(order)
              scope = order.attendees.includes(
                { ticket: %i[tickets_translations ticket_meal_slots] },
                { event: :events_translations },
                attendee_boolean_field_responses: { event_boolean_field: :event_boolean_field_translations }
              )
              (order.user_id == current_user.id ? scope : scope.where(user_id: current_user.id)).to_a
            end

            def update_boolean_responses(attendee)
              event_field_ids = attendee.event.event_boolean_fields.pluck(:id)
              Array(params[:boolean_field_responses]).each do |r|
                field_id = r[:event_boolean_field_id].to_i
                next unless event_field_ids.include?(field_id)

                response = attendee.attendee_boolean_field_responses.find_or_initialize_by(
                  event_boolean_field_id: field_id
                )
                response.value = r[:value]
                response.save!
              end
            end

            def orders_for_user_scoped_to(where_clause:, sort:)
              # Include orders where user is a non-cancelled attendee OR where user created the order
              ordered_order_ids =
                Order.joins(attendees: :event)
                     .where(events: { status: Event.statuses[:live] })
                     .where(where_clause, Time.current)
                     .where(
                       'orders.user_id = :uid OR (attendees.user_id = :uid AND attendees.payment_status != :cancelled)',
                       uid: current_user.id,
                       cancelled: Attendee.payment_statuses[:attendee_cancelled]
                     )
                     .order(sort)
                     .pluck('orders.id')
                     .uniq

              orders_by_id = Order.where(id: ordered_order_ids).index_by(&:id)
              ordered_order_ids.filter_map { |id| orders_by_id[id] }
            end

            def serialise_orders(orders) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
              return [] if orders.empty?

              own_order_ids   = orders.select { |o| o.user_id == current_user.id }.map(&:id)
              other_order_ids = orders.reject { |o| o.user_id == current_user.id }.map(&:id)

              attendees_by_order = {}

              attendee_includes = [
                { ticket: %i[tickets_translations ticket_meal_slots] },
                { event: [:events_translations, { event_template_docs: :event_template_doc_translations }] },
                { attendee_boolean_field_responses: { event_boolean_field: :event_boolean_field_translations } }
              ]

              if own_order_ids.any?
                Attendee.where(order_id: own_order_ids)
                        .includes(*attendee_includes)
                        .group_by(&:order_id)
                        .each { |oid, atts| attendees_by_order[oid] = atts }
              end

              if other_order_ids.any?
                Attendee.where(order_id: other_order_ids, user_id: current_user.id)
                        .includes(*attendee_includes)
                        .group_by(&:order_id)
                        .each { |oid, atts| attendees_by_order[oid] = atts }
              end

              orders.filter_map { |order| serialise_order(order, attendees_by_order[order.id] || []) }
            end

            def serialise_order(order, attendees)
              return nil if attendees.empty?

              event = attendees.first.event
              lang  = current_user.language || 'ro-RO'

              {
                order_reference: order.order_reference,
                payment_status: order.payment_status(attendees),
                total_price: attendees.sum { |a| a.ticket&.price || 0 },
                event: serialise_event(event, lang, attendees),
                attendees: attendees.map { |a| serialise_attendee(a, lang) }
              }
            end

            def serialise_event(event, lang, attendees = [])
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

            def serialise_template_docs(docs, lang, attendees)
              attendee_ages = attendees.map(&:age)
              docs.select { |doc| doc_applies_to_any_attendee?(doc, attendee_ages) }
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

            def doc_applies_to_any_attendee?(doc, ages)
              return true if doc.age_from.nil? && doc.age_to.nil?

              ages.any? do |age|
                next false if age.nil?

                (doc.age_from.nil? || age >= doc.age_from) &&
                  (doc.age_to.nil? || age <= doc.age_to)
              end
            end

            def serialise_attendee(attendee, lang)
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
  end
end
