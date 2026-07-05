"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "../supabase/server";

export async function createTeam(_prevState: unknown, formData: FormData) {
    const name = formData.get("name") as string;
    const slug = formData.get("slug") as string;
    const supabase = await createClient();

    const { data, error } = await supabase.rpc("create_account", { name, slug });

    if (error) {
        return { message: error.message };
    }

    revalidatePath("/dashboard", "layout");
    redirect(`/dashboard/${data.slug}`);
}

export async function editTeamName(_prevState: unknown, formData: FormData) {
    const name = formData.get("name") as string;
    const accountId = formData.get("accountId") as string;
    const supabase = await createClient();

    const { error } = await supabase.rpc("update_account", { name, account_id: accountId });

    if (error) {
        return { message: error.message };
    }

    revalidatePath("/dashboard", "layout");
    return { message: null };
}

export async function editTeamSlug(_prevState: unknown, formData: FormData) {
    const slug = formData.get("slug") as string;
    const accountId = formData.get("accountId") as string;
    const supabase = await createClient();

    const { data, error } = await supabase.rpc("update_account", { slug, account_id: accountId });

    if (error) {
        return { message: error.message };
    }

    revalidatePath("/dashboard", "layout");
    redirect(`/dashboard/${data.slug}/settings`);
}
