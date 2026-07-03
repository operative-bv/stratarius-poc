import { redirect } from "next/navigation";

export default async function PersonalAccountBillingPage() {
  redirect("/dashboard/settings");
}
