# frozen_string_literal: true

class CheckPaymentAddressWorker
  include Sidekiq::Job
  sidekiq_options retry: 0, queue: :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.can_flag_for_fraud?

    should_flag = fraud_signal_detected?(user)
    if should_flag
      user.flag_for_fraud!(author_name: "CheckPaymentAddress")
      return
    end

    matching_suspended_tos_user = suspended_tos_user_with_matching_payment_address(user) ||
      suspended_tos_user_with_matching_stripe_fingerprint(user)
    return unless matching_suspended_tos_user

    user.put_on_probation!(
      author_name: "CheckPaymentAddress",
      content: "Probated (payouts suspended) automatically on #{Time.current.to_fs(:formatted_date_full_month)} because this account matches payout details of User##{matching_suspended_tos_user.id} (UID: #{matching_suspended_tos_user.external_id}) suspended for a policy violation"
    )
  end

  private
    def fraud_signal_detected?(user)
      suspended_fraud_user_with_matching_payment_address(user).present? ||
        suspended_fraud_user_with_matching_stripe_fingerprint(user).present? ||
        blocked_email_exists?(user) ||
        blocked_fingerprint_exists?(user)
    end

    def suspended_fraud_user_with_matching_payment_address(user)
      return false if user.payment_address.blank?

      User.where(
        payment_address: user.payment_address,
        user_risk_state: "suspended_for_fraud"
      ).where.not(id: user.id).first
    end

    def suspended_tos_user_with_matching_payment_address(user)
      return false if user.payment_address.blank?

      User.where(
        payment_address: user.payment_address,
        user_risk_state: "suspended_for_tos_violation"
      ).where.not(id: user.id).first
    end

    def suspended_fraud_user_with_matching_stripe_fingerprint(user)
      fingerprints = user.alive_bank_accounts.where.not(stripe_fingerprint: [nil, ""]).distinct.pluck(:stripe_fingerprint)
      return false if fingerprints.empty?

      User
        .joins(:bank_accounts)
        .merge(BankAccount.alive.where(stripe_fingerprint: fingerprints))
        .where.not(users: { id: user.id })
        .where(user_risk_state: "suspended_for_fraud")
        .distinct
        .first
    end

    def suspended_tos_user_with_matching_stripe_fingerprint(user)
      fingerprints = user.alive_bank_accounts.where.not(stripe_fingerprint: [nil, ""]).distinct.pluck(:stripe_fingerprint)
      return false if fingerprints.empty?

      User
        .joins(:bank_accounts)
        .merge(BankAccount.alive.where(stripe_fingerprint: fingerprints))
        .where.not(users: { id: user.id })
        .where(user_risk_state: "suspended_for_tos_violation")
        .distinct
        .first
    end

    def blocked_email_exists?(user)
      return false if user.payment_address.blank?

      BlockedObject.find_active_object(user.payment_address).present?
    end

    def blocked_fingerprint_exists?(user)
      fingerprints = user.alive_bank_accounts.where.not(stripe_fingerprint: [nil, ""]).distinct.pluck(:stripe_fingerprint)
      return false if fingerprints.empty?

      BlockedObject.find_active_objects(fingerprints).present?
    end
end
