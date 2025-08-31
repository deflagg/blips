// src/components/UsersPage.jsx
import { useEffect, useState } from 'react'

export default function UsersPage() {
  const [users, setUsers]   = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError]   = useState(null)
  const [busy, setBusy]     = useState(false)
  const [form, setForm]     = useState({ name: '', email: '' })

  // Replace these endpoints with your real user service
  const api = {
    list:   async () => { const r = await fetch('/api/users'); if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json() },
    create: async (u) => { const r = await fetch('/api/users', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(u)}); if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json() },
    remove: async (id) => { const r = await fetch(`/api/users/${id}`, { method:'DELETE' }); if (!r.ok) throw new Error(`HTTP ${r.status}`) },
  }

  const refresh = async () => {
    setLoading(true); setError(null)
    try {
      const data = await api.list()
      // accept either {items:[...]} or [...]
      setUsers(Array.isArray(data?.items) ? data.items : (Array.isArray(data) ? data : []))
    } catch (e) {
      setError(e.message || 'Failed to load users')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { refresh() }, [])

  const onSubmit = async (e) => {
    e.preventDefault()
    if (!form.name.trim() || !form.email.trim()) return
    try {
      setBusy(true); setError(null)
      await api.create(form)
      setForm({ name: '', email: '' })
      await refresh()
    } catch (e) {
      setError(e.message || 'Create failed')
    } finally {
      setBusy(false)
    }
  }

  const onDelete = async (id) => {
    if (!confirm('Delete this user?')) return
    try {
      setBusy(true)
      await api.remove(id)
      await refresh()
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="grid">
      <section className="col col--compose">
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Create user</h2>
            <p className="card-subtitle">Add a new person to Blips.</p>
          </div>
          <div className="card-body">
            <form onSubmit={onSubmit} className="form" style={{ display:'grid', gap:'0.75rem' }}>
              <div>
                <label htmlFor="u-name" className="label">Name</label>
                <input id="u-name" className="input" value={form.name}
                       onChange={e => setForm(f => ({...f, name: e.target.value}))} />
              </div>
              <div>
                <label htmlFor="u-email" className="label">Email</label>
                <input id="u-email" type="email" className="input" value={form.email}
                       onChange={e => setForm(f => ({...f, email: e.target.value}))} />
              </div>
              <button className="btn btn-primary" disabled={busy}>
                {busy ? 'Saving…' : 'Create user'}
              </button>
            </form>
            {error && <div role="alert" className="alert alert-error" style={{ marginTop: 12 }}>Error: {error}</div>}
          </div>
        </div>
      </section>

      <section className="col col--feed">
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Users</h2>
            <p className="card-subtitle">Manage existing users.</p>
          </div>
          <div className="card-body">
            {loading ? (
              <div className="loading"><div className="spinner" aria-hidden="true"></div><span className="muted">Loading users…</span></div>
            ) : users.length === 0 ? (
              <div className="empty">No users yet.</div>
            ) : (
              <ul className="feed-list">
                {users.map(u => (
                  <li key={u.id} className="feed-item">
                    <div className="avatar" aria-hidden="true">{(u.name || '?').slice(0,2).toUpperCase()}</div>
                    <div className="feed-content">
                      <div className="feed-meta">
                        <span className="feed-user">{u.name || '(no name)'}</span>
                        <span className="dot">•</span>
                        <span className="muted">{u.email}</span>
                        <span className="chip">#{u.id}</span>
                      </div>
                      <div style={{ display:'flex', gap:'0.5rem' }}>
                        <button className="btn" onClick={() => onDelete(u.id)} disabled={busy}>Delete</button>
                        {/* Add more controls: suspend, reset password, set role, etc. */}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </section>
    </div>
  )
}
