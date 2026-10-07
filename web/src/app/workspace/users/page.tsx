"use client";

import { useCallback, useEffect, useState } from "react";
import { WorkspaceShell } from "@/components/layout/WorkspaceShell";
import { Button, ErrorNote, Field, inputStyle, Notice } from "@/components/ui/Form";
import { api, errorText, type Permission, type ShopUser } from "@/lib/api";
import { hasPermission, useSession } from "@/lib/session";

// SCR-SHP-013. Permissions go straight onto each user, there are no roles (D050).
export default function UsersPage() {
  const session = useSession();
  const canManage = hasPermission(session?.user, "shop.users.manage");

  const [users, setUsers] = useState<ShopUser[]>([]);
  const [catalogue, setCatalogue] = useState<Permission[]>([]);
  const [editing, setEditing] = useState<ShopUser | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    Promise.all([api.shop.users(), api.shop.permissions()])
      .then(([u, p]) => {
        if (cancelled) return;
        setUsers(u);
        setCatalogue(p);
      })
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [attempt]);

  async function toggle(user: ShopUser) {
    setError(null);
    try {
      if (user.disabled) {
        await api.shop.enable(user.id);
      } else {
        await api.shop.disable(user.id);
      }
      reload();
    } catch (e) {
      setError(errorText(e));
    }
  }

  const names = Object.fromEntries(catalogue.map((p) => [p.code, p.name]));

  return (
    <WorkspaceShell screenId="SCR-SHP-013">
      <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>Users &amp; Permissions</h1>
      <p className="mb-5 text-sm" style={{ color: "var(--text-secondary)" }}>
        Manage Shop users and assign permissions directly to each user.
      </p>

      <div className="mb-6 flex items-center justify-between gap-4 p-4" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: 4 }}>
        <p className="text-xs" style={{ color: "var(--text-secondary)" }}>
          <strong>Shop Administrator</strong> has the full permission set, which can&apos;t be reduced. All changes are audited.
        </p>
        {canManage && (
          <Button type="button" wide={false} onClick={() => setEditing("new")}>Invite User</Button>
        )}
      </div>

      <ErrorNote message={error} />
      {notice && <Notice>{notice}</Notice>}

      <h2 className="mb-2 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>Users</h2>
      <div className="overflow-x-auto" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)" }}>
        <table className="w-full text-left text-sm">
          <thead style={{ background: "var(--surface-sunken)" }}>
            <tr className="text-xs" style={{ color: "var(--text-secondary)" }}>
              <th className="px-4 py-3">Name</th>
              <th className="px-4 py-3">Email</th>
              <th className="px-4 py-3">Permissions summary</th>
              <th className="px-4 py-3">Status</th>
              {canManage && <th className="px-4 py-3">Actions</th>}
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id} style={{ borderTop: "1px solid var(--border-subtle)", color: "var(--text-primary)" }}>
                <td className="px-4 py-3">{u.fullName}</td>
                <td className="px-4 py-3">{u.email}</td>
                <td className="px-4 py-3 text-xs" style={{ color: "var(--text-secondary)" }}>
                  {u.isAdministrator ? "Full permissions — fixed" : u.permissions.map((c) => names[c] ?? c).join(" · ") || "None"}
                </td>
                <td className="px-4 py-3 text-xs">{u.disabled ? "Disabled" : u.pending ? "Pending" : "Active"}</td>
                {canManage && (
                  <td className="px-4 py-3 text-xs">
                    {!u.isAdministrator && (
                      <>
                        <button type="button" className="mr-3 font-semibold hover:underline" style={{ color: "var(--philmart-navy-deep)" }} onClick={() => setEditing(u)}>
                          Edit
                        </button>
                        {u.id !== session?.user.actorID && (
                          <button type="button" className="font-semibold hover:underline" style={{ color: u.disabled ? "var(--accent-live)" : "var(--accent-danger)" }} onClick={() => toggle(u)}>
                            {u.disabled ? "Reactivate" : "Disable"}
                          </button>
                        )}
                      </>
                    )}
                    {u.isAdministrator && <span style={{ color: "var(--text-muted)" }}>View</span>}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="mb-2 mt-8 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>Permission model</h2>
      <div className="p-4 text-xs leading-6" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", color: "var(--text-secondary)" }}>
        <p className="font-semibold" style={{ color: "var(--text-primary)" }}>Permissions are assigned directly to each user.</p>
        <p>There are no custom Shop roles. Editing a user changes only that user&apos;s permissions.</p>
        <p>Disabling a user removes access but keeps all their past actions and audit history.</p>
        <p>The Shop Administrator keeps the full permission set and can&apos;t be reduced.</p>
      </div>

      {editing && (
        <UserDialog
          user={editing === "new" ? null : editing}
          catalogue={catalogue}
          onClose={() => setEditing(null)}
          onSaved={(message) => {
            setEditing(null);
            setNotice(message);
            reload();
          }}
        />
      )}
    </WorkspaceShell>
  );
}

function UserDialog({
  user,
  catalogue,
  onClose,
  onSaved,
}: {
  user: ShopUser | null;
  catalogue: Permission[];
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const [email, setEmail] = useState("");
  const [fullName, setFullName] = useState("");
  const [chosen, setChosen] = useState<string[]>(user?.permissions ?? []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const categories = Array.from(new Set(catalogue.map((p) => p.category)));

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (user) {
        await api.shop.setPermissions(user.id, chosen);
        onSaved(`${user.fullName}'s permissions were updated.`);
      } else {
        const res = await api.shop.invite({ email, fullName, permissions: chosen });
        onSaved(`Invitation created. Send ${fullName} this link to set their password: ${res.invitationLink}`);
      }
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto p-4" style={{ background: "rgb(15 23 42 / 0.5)" }} role="dialog" aria-modal="true">
      <form onSubmit={save} className="mt-10 w-full max-w-2xl p-6" style={{ background: "var(--surface-card)", borderRadius: "var(--radius-card)" }}>
        <h2 className="mb-1 font-display text-2xl font-bold" style={{ color: "var(--text-primary)" }}>
          {user ? "Edit User Permissions" : "Invite User"}
        </h2>
        <p className="mb-4 text-xs" style={{ color: "var(--text-muted)" }}>
          {user ? `${user.fullName} · ${user.email}` : "Permissions are given directly to this user."}
        </p>

        <ErrorNote message={error} />

        {!user && (
          <div className="grid grid-cols-2 gap-4">
            <Field label="Full name" htmlFor="name">
              <input id="name" required value={fullName} onChange={(e) => setFullName(e.target.value)} style={inputStyle} />
            </Field>
            <Field label="Email" htmlFor="invite-email">
              <input id="invite-email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} style={inputStyle} />
            </Field>
          </div>
        )}

        <div className="mb-5 grid grid-cols-2 gap-x-6 gap-y-3">
          {categories.map((cat) => (
            <fieldset key={cat}>
              <legend className="mb-1 text-xs font-bold" style={{ color: "var(--text-secondary)" }}>{cat}</legend>
              {catalogue
                .filter((p) => p.category === cat)
                .map((p) => (
                  <label key={p.code} className="flex items-center gap-2 py-0.5 text-sm" style={{ color: p.adminOnly ? "var(--text-muted)" : "var(--text-primary)" }} title={p.description}>
                    <input
                      type="checkbox"
                      disabled={p.adminOnly}
                      checked={chosen.includes(p.code)}
                      onChange={(e) => setChosen((c) => (e.target.checked ? [...c, p.code] : c.filter((x) => x !== p.code)))}
                    />
                    {p.name}
                    {p.adminOnly && <span className="text-[10px]">(administrator only)</span>}
                  </label>
                ))}
            </fieldset>
          ))}
        </div>

        <div className="grid grid-cols-2 gap-4">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button disabled={busy}>{user ? "Save permissions" : "Create invitation"}</Button>
        </div>
      </form>
    </div>
  );
}
