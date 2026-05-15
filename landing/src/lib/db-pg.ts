import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let clientInstance: SupabaseClient | null = null;

function getClient(): SupabaseClient {
  if (clientInstance) return clientInstance;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      "Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY. Add them in Vercel project env.",
    );
  }
  clientInstance = createClient(url, key, {
    auth: { persistSession: false },
  });
  return clientInstance;
}

export type SubmissionStatus = "pending" | "approved" | "rejected";

export interface Submission {
  id: number;
  email: string;
  name: string | null;
  proof_path: string;
  status: SubmissionStatus;
  license_key: string | null;
  notes: string | null;
  created_at: string;
  reviewed_at: string | null;
}

export interface License {
  key: string;
  email: string;
  plan: string;
  status: "active" | "revoked" | "expired";
  issued_at: string;
  expires_at: string;
}

export interface Activation {
  id: number;
  license_key: string;
  machine_id: string;
  machine_label: string | null;
  activated_at: string;
  last_seen_at: string;
  deactivated_at: string | null;
}

export const queries = {
  async insertSubmission(args: {
    email: string;
    name: string | null;
    proofPath: string;
  }): Promise<Submission> {
    const { data, error } = await getClient()
      .from("submissions")
      .insert({
        email: args.email,
        name: args.name,
        proof_path: args.proofPath,
      })
      .select()
      .single();
    if (error) throw error;
    return data as Submission;
  },

  async listSubmissions(
    filter?: SubmissionStatus | "all",
  ): Promise<Submission[]> {
    const q = getClient()
      .from("submissions")
      .select("*")
      .order("created_at", { ascending: false });
    const { data, error } =
      !filter || filter === "all" ? await q : await q.eq("status", filter);
    if (error) throw error;
    return (data ?? []) as Submission[];
  },

  async getSubmission(id: number): Promise<Submission | undefined> {
    const { data, error } = await getClient()
      .from("submissions")
      .select("*")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    return (data as Submission) ?? undefined;
  },

  async approveSubmission(
    id: number,
    licenseKey: string,
    notes?: string | null,
  ): Promise<Submission | undefined> {
    const patch: Record<string, unknown> = {
      status: "approved",
      license_key: licenseKey,
      reviewed_at: new Date().toISOString(),
    };
    if (notes != null) patch.notes = notes;
    const { data, error } = await getClient()
      .from("submissions")
      .update(patch)
      .eq("id", id)
      .neq("status", "approved")
      .select()
      .maybeSingle();
    if (error) throw error;
    return (data as Submission) ?? undefined;
  },

  async rejectSubmission(
    id: number,
    notes?: string | null,
  ): Promise<Submission | undefined> {
    const patch: Record<string, unknown> = {
      status: "rejected",
      reviewed_at: new Date().toISOString(),
    };
    if (notes != null) patch.notes = notes;
    const { data, error } = await getClient()
      .from("submissions")
      .update(patch)
      .eq("id", id)
      .eq("status", "pending")
      .select()
      .maybeSingle();
    if (error) throw error;
    return (data as Submission) ?? undefined;
  },

  async countByStatus(): Promise<Record<SubmissionStatus, number>> {
    const out: Record<SubmissionStatus, number> = {
      pending: 0,
      approved: 0,
      rejected: 0,
    };
    const client = getClient();
    for (const s of ["pending", "approved", "rejected"] as SubmissionStatus[]) {
      const { count, error } = await client
        .from("submissions")
        .select("*", { count: "exact", head: true })
        .eq("status", s);
      if (error) throw error;
      out[s] = count ?? 0;
    }
    return out;
  },

  async upsertLicense(args: {
    key: string;
    email: string;
    plan?: string;
    expiresAt: Date;
  }): Promise<License> {
    const { data, error } = await getClient()
      .from("licenses")
      .upsert(
        {
          key: args.key,
          email: args.email,
          plan: args.plan ?? "annual",
          expires_at: args.expiresAt.toISOString(),
        },
        { onConflict: "key" },
      )
      .select()
      .single();
    if (error) throw error;
    return data as License;
  },

  async getLicense(key: string): Promise<License | undefined> {
    const { data, error } = await getClient()
      .from("licenses")
      .select("*")
      .eq("key", key)
      .maybeSingle();
    if (error) throw error;
    return (data as License) ?? undefined;
  },

  async getActiveActivation(
    licenseKey: string,
  ): Promise<Activation | undefined> {
    const { data, error } = await getClient()
      .from("activations")
      .select("*")
      .eq("license_key", licenseKey)
      .is("deactivated_at", null)
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    return (data as Activation) ?? undefined;
  },

  async countRecentDeactivations(
    licenseKey: string,
    sinceDays = 30,
  ): Promise<number> {
    const since = new Date(Date.now() - sinceDays * 86_400_000).toISOString();
    const { count, error } = await getClient()
      .from("activations")
      .select("*", { count: "exact", head: true })
      .eq("license_key", licenseKey)
      .not("deactivated_at", "is", null)
      .gt("deactivated_at", since);
    if (error) throw error;
    return count ?? 0;
  },

  async insertActivation(args: {
    licenseKey: string;
    machineId: string;
    machineLabel: string | null;
  }): Promise<Activation> {
    const { data, error } = await getClient()
      .from("activations")
      .insert({
        license_key: args.licenseKey,
        machine_id: args.machineId,
        machine_label: args.machineLabel,
      })
      .select()
      .single();
    if (error) throw error;
    return data as Activation;
  },

  async heartbeatActivation(
    licenseKey: string,
    machineId: string,
  ): Promise<Activation | undefined> {
    const { data, error } = await getClient()
      .from("activations")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("license_key", licenseKey)
      .eq("machine_id", machineId)
      .is("deactivated_at", null)
      .select()
      .maybeSingle();
    if (error) throw error;
    return (data as Activation) ?? undefined;
  },

  async deactivateActivation(
    licenseKey: string,
    machineId: string,
  ): Promise<Activation | undefined> {
    const { data, error } = await getClient()
      .from("activations")
      .update({ deactivated_at: new Date().toISOString() })
      .eq("license_key", licenseKey)
      .eq("machine_id", machineId)
      .is("deactivated_at", null)
      .select()
      .maybeSingle();
    if (error) throw error;
    return (data as Activation) ?? undefined;
  },
};
