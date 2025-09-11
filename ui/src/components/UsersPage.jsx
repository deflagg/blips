// src/components/UsersPage.jsx
import { useEffect, useState } from 'react'
import axios from 'axios'

// --- Axios client (mirrors blipPost style) ---
// --- Axios client (mirrors blipPost style) ---
const API_BASE_URL = (import.meta.env?.VITE_API_BASE_URL || '').replace(/\/+$/, '')

const http = axios.create({
  baseURL: API_BASE_URL || undefined, // falls back to relative requests if unset
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
})

// Read RU header like in blipPost
const parseRu = (res) => {
  const h = res?.headers?.['x-ms-request-charge']
  const ru = h ? parseFloat(Array.isArray(h) ? h[0] : h) : 0
  return Number.isFinite(ru) ? ru : 0
}

// Uniform error message extraction (works with problem/json, strings, etc.)
const getErr = (err) =>
  err?.response?.data?.error ||
  err?.response?.data?.message ||
  (typeof err?.response?.data === 'string' ? err.response.data : '') ||
  err.message ||
  'Request failed'

// Minimal API wrapper for Accounts
const api = {
  // NOTE: This assumes a GET /accounts endpoint that returns an array of accounts.
  // If you don't have it yet, see the note after the component.
  list: async (skip = 0, take = 100) => {
    const res = await http.get('/accounts', { params: { skip, take } })
    return { items: Array.isArray(res.data) ? res.data : (Array.isArray(res.data?.items) ? res.data.items : []), ru: parseRu(res) }
  },

  // POST /accounts/ expects: { id, name, email }
  create: async ({ name, email }) => {
    const id =
      (globalThis.crypto?.randomUUID?.() ??
        `${Date.now()}-${Math.random().toString(16).slice(2)}`)

    const payload = { name: name, email: email }
    const res = await http.post('/accounts/', payload)
    return { data: res.data, ru: parseRu(res) }
  },

  // DELETE /accounts/{id}
  remove: async (id) => {
    const res = await http.delete(`/accounts/${encodeURIComponent(id)}`)
    return { ru: parseRu(res) }
  },
}

export default function UsersPage() {
  const [users, setUsers]   = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError]   = useState(null)
  const [busy, setBusy]     = useState(false)
  const [form, setForm]     = useState({ name: '', email: '' })
  const [lastRu, setLastRu] = useState(null)

  const refresh = async () => {
    setLoading(true); setError(null)
    try {
      const { items, ru } = await api.list()
      setUsers(items)
      setLastRu(ru)
    } catch (e) {
      setError(getErr(e))
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
      const { ru } = await api.create(form)
      setForm({ name: '', email: '' })
      setLastRu(ru)
      await refresh()
    } catch (e) {
      setError(getErr(e))
    } finally {
      setBusy(false)
    }
  }

  const onDelete = async (id) => {
    if (!confirm('Delete this user?')) return
    try {
      setBusy(true); setError(null)
      const { ru } = await api.remove(id)
      setLastRu(ru)
      await refresh()
    } catch (e) {
      setError(getErr(e))
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

            {/* RU badge (last operation) */}
            <div className="metrics right" style={{ marginTop: 8 }}>
              <span className="chip">Last RU: {lastRu != null ? lastRu.toFixed(3) : '—'}</span>
            </div>

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
                    <div className="avatar" aria-hidden="true">{(u.Name || u.name || '?').slice(0,2).toUpperCase()}</div>
                    <div className="feed-content">
                      <div className="feed-meta">
                        <span className="feed-user">{u.Name || u.name || '(no name)'}</span>
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
