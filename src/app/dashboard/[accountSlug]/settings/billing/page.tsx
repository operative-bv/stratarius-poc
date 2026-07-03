import { redirect } from "next/navigation";

export default async function TeamBillingPage({ params: { accountSlug } }: { params: { accountSlug: string } }) {
  redirect(`/dashboard/${accountSlug}/settings`);
}
