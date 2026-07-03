-- T-039: team-only tenant model per N-007 decision.
-- Personal accounts continue to be auto-created for auth; their billing UI is disabled.
-- Basejump does not expose an enable_personal_accounts flag — personal_accounts always
-- exist (bound to user.id). This migration disables the personal-account billing surface
-- so that Stripe UI is never rendered for personal accounts.
update basejump.config set enable_personal_account_billing = false;
