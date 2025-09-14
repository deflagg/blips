// src/components/UsersPage.jsx
import { useState, useRef, useEffect } from 'react'
import axios from 'axios'

// --- Axios client ---
const API_BASE_URL = (import.meta.env?.VITE_API_BLIP_USER_ADMIN || '').replace(/\/+$/, '')

const http = axios.create({
  baseURL: API_BASE_URL || undefined, // falls back to relative requests if unset
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
})

// Read RU header (Cosmos)
const parseRu = (res) => {
  const h = res?.headers?.['x-ms-request-charge']
  const ru = h ? parseFloat(Array.isArray(h) ? h[0] : h) : 0
  return Number.isFinite(ru) ? ru : 0
}

// Uniform error message extraction
const getErr = (err) =>
  err?.response?.data?.error ||
  err?.response?.data?.message ||
  (typeof err?.response?.data === 'string' ? err.response.data : '') ||
  err.message ||
  'Request failed'

// Minimal API wrapper
const api = {
  // POST /accounts expects: { name, email }
  create: async ({ name, email }) => {
    const payload = { name, email }
    const res = await http.post('/accounts', payload)
    return { data: res.data, ru: parseRu(res) }
  },
}

export default function UsersPage() {
  const [form, setForm]       = useState({ name: '', email: '' })
  const [busy, setBusy]       = useState(false)
  const [error, setError]     = useState(null)
  const [lastRu, setLastRu]   = useState(null)

  // Success indicators (no buttons, no ids)
  const [success, setSuccess]       = useState(null) // { name, email, at }
  const [seedSuccess, setSeedSuccess] = useState(null) // { createdUsers, followEdges, at }
  const toastTimerRef  = useRef(null)
  const seedTimerRef   = useRef(null)

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current)
      if (seedTimerRef.current) clearTimeout(seedTimerRef.current)
    }
  }, [])

  const onSubmit = async (e) => {
    e.preventDefault()
    const name  = form.name.trim()
    const email = form.email.trim()
    if (!name || !email) return

    try {
      setBusy(true); setError(null)
      const { data, ru } = await api.create({ name, email })
      setLastRu(ru)

      setSuccess({
        name:  data?.name ?? data?.Name ?? name,
        email: data?.email ?? data?.Email ?? email,
        at:    new Date(),
      })
      setForm({ name: '', email: '' })

      if (toastTimerRef.current) clearTimeout(toastTimerRef.current)
      toastTimerRef.current = setTimeout(() => setSuccess(null), 4500)
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
          <div className="card-header" style={{ display:'flex', alignItems:'center', gap:12 }}>
            <div style={{ flex: 1 }}>
              <h2 className="card-title">Create user</h2>
              <p className="card-subtitle">Add a new person to Blips.</p>
            </div>
          </div>

          <div className="card-body" style={{ display: 'grid', gap: '0.75rem' }}>
            {/* Success banners (no buttons, no id) */}
            <div aria-live="polite" aria-atomic="true" style={{ display:'grid', gap:8 }}>
              {success && (
                <div className="alert alert-success" role="status" style={{ display:'flex', alignItems:'center', gap:'0.75rem' }}>
                  <span aria-hidden="true">✅</span>
                  <div style={{ lineHeight: 1.3 }}>
                    <strong>User created</strong>
                    <div className="muted" style={{ marginTop: 2 }}>
                      {success.name} &lt;{success.email}&gt;
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Form */}
            <form onSubmit={onSubmit} className="form" style={{ display:'grid', gap:'0.75rem' }}>
              <div>
                <label htmlFor="u-name" className="label">Name</label>
                <input
                  id="u-name"
                  className="input"
                  value={form.name}
                  onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                  disabled={busy}
                  autoComplete="name"
                />
              </div>

              <div>
                <label htmlFor="u-email" className="label">Email</label>
                <input
                  id="u-email"
                  type="email"
                  className="input"
                  value={form.email}
                  onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
                  disabled={busy}
                  autoComplete="email"
                />
              </div>

              <button className="btn btn-primary" disabled={busy || !form.name.trim() || !form.email.trim()}>
                {busy ? 'Saving…' : 'Create user'}
              </button>
            </form>

            {/* RU badge (last operation) */}
            <div className="metrics right" style={{ marginTop: 4 }}>
              <span className="chip">Last RU: {lastRu != null ? lastRu.toFixed(3) : '—'}</span>
            </div>

            {error && (
              <div role="alert" className="alert alert-error" style={{ marginTop: 8 }}>
                Error: {error}
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Intentionally no "Users" list for scalability */}
    </div>
  )
}
