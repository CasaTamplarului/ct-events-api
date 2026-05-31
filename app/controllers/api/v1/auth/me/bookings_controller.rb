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
              where_clause: 'events.start_date > ?',
              sort: 'events.start_date ASC'
            )
            render json: serialise_orders(orders)
          end

          def past
            orders = orders_for_user_scoped_to(
              where_clause: 'events.end_date <= ?',
              sort: 'events.start_date DESC'
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

            # rubocop:disable Rails/SkipsModelValidations
            cancellable.update_all(payment_status: Attendee.payment_statuses['attendee_cancelled'])
            # rubocop:enable Rails/SkipsModelValidations

            attendees = order.attendees
                             .includes({ ticket: :tickets_translations }, { event: :events_translations })
                             .where(user_id: current_user.id)
                             .to_a
            render json: serialise_order(order, attendees)
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

            attendee.update!(payment_status: :attendee_cancelled)

            attendees = order.attendees
                             .includes({ ticket: :tickets_translations }, { event: :events_translations })
                             .where(user_id: current_user.id)
                             .to_a
            render json: serialise_order(order, attendees)
          end

          private

            def orders_for_user_scoped_to(where_clause:, sort:)
              # Collect ordered, distinct order IDs via attendees (avoids DISTINCT + ORDER BY conflict)
              ordered_order_ids =
                Attendee.joins(:event)
                        .where(user_id: current_user.id)
                        .where.not(payment_status: :attendee_cancelled)
                        .where(where_clause, Time.current)
                        .where(events: { status: Event.statuses[:live] })
                        .order(sort)
                        .pluck(:order_id)
                        .uniq

              # Load and return orders preserving the correct sort order
              orders_by_id = Order.where(id: ordered_order_ids).index_by(&:id)
              ordered_order_ids.filter_map { |id| orders_by_id[id] }
            end

            def serialise_orders(orders)
              return [] if orders.empty?

              order_ids = orders.map(&:id)
              attendees_by_order = Attendee
                                   .where(order_id: order_ids, user_id: current_user.id)
                                   .includes({ ticket: :tickets_translations }, { event: :events_translations })
                                   .group_by(&:order_id)

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
                event: serialise_event(event, lang),
                attendees: attendees.map { |a| serialise_attendee(a, lang) }
              }
            end

            def serialise_event(event, lang)
              name = event.events_translations.find { |t| t.languages_code == lang }&.name ||
                     event.events_translations.find { |t| t.languages_code == 'ro-RO' }&.name
              {
                name: name,
                slug: event.slug,
                start_date: event.start_date,
                end_date: event.end_date,
                location_name: event.location_name,
                address: event.address
              }
            end

            def serialise_attendee(attendee, lang)
              translation = ticket_translation_for(attendee, lang)
              {
                first_name: attendee.first_name,
                last_name: attendee.last_name,
                ticket_name: translation&.name,
                ticket_description: translation&.description,
                ticket_price: attendee.ticket&.price,
                food_included: attendee.ticket&.food_included,
                dietary_preference: attendee.dietary_preference
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
