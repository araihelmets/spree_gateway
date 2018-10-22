module Spree
  class Gateway::AuthorizeNet < Gateway
    preference :login, :string
    preference :password, :string
    preference :server, :string, default: "test"

    def provider_class
      ActiveMerchant::Billing::AuthorizeNetGateway
    end

    def options_with_test_preference
      if !['live','test'].include?(self.preferred_server)
        raise "You must set the 'server' preference in your payment method (Gateway::AuthorizeNet) to either 'live' or 'test'"
      end
      options_without_test_preference.merge(test: (self.preferred_server != "live") )
    end

    def cancel(response_code)
      provider
      # From: http://community.developer.authorize.net/t5/The-Authorize-Net-Developer-Blog/Refunds-in-Retail-A-user-friendly-approach-using-AIM/ba-p/9848
      # DD: if unsettled, void needed
      response = provider.void(response_code)
      # DD: if settled, credit/refund needed (CAN'T DO WITHOUT CREDIT CARD ON AUTH.NET)
      #response = provider.refund(response_code) unless response.success?

      response
    end
    alias_method_chain :options, :test_preference

    def credit(amount, response_code, refund, gateway_options = {})
      gateway_options[:card_number] = refund[:originator].payment.source.last_digits
      auth_net_gateway.refund(amount, response_code, gateway_options)
    end

    # 2018-02-04 11:01:39 AV
    # ARAI > Dev > Credit Cards > Removal > Overriding Authorize.net gateway methods to only show non soft-deleted credit cards
    def sources_by_order(order)
      source_ids = order.payments.where(source_type: payment_source_class.to_s, payment_method_id: id).pluck(:source_id).uniq
      payment_source_class.where(id: source_ids).with_payment_profile
    end

    # 2018-02-04 11:01:48 AV
    # ARAI > Dev > Credit Cards > Removal > Overriding Authorize.net gateway methods to only show non soft-deleted credit cards
    def reusable_sources(order)

      logger.info "###############################"
      logger.info "Inside reusable_sources"
      logger.info Time.now.getlocal('-08:00')
      logger.info "###############################"

      if order.completed?
        logger.info "Step 0"
        sources_by_order order
      else
        if order.user_id
          logger.info "Step 1"
          # credit_cards.where(user_id: order.user_id).with_payment_profile
          # credit_cards.where(user_id: order.user_id, soft_delete: false).with_payment_profile
          @cc = credit_cards.where(user_id: order.user_id, soft_delete: false).with_payment_profile
          return @cc
        else
          logger.info "Step 2"
          []
        end
      end
    end

    private

    def auth_net_gateway
      @_auth_net_gateway ||= begin
        ActiveMerchant::Billing::Base.gateway_mode = preferred_server.to_sym
        gateway_options = options
        gateway_options[:test_requests] = false # DD: never ever do test requests because just returns transaction_id = 0
        ActiveMerchant::Billing::AuthorizeNetGateway.new(gateway_options)
      end
    end
  end
end
