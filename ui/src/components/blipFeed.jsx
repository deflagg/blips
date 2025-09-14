// src/components/BlipFeed.jsx
import { useState, useEffect } from 'react'
import axios from 'axios'

// --- Axios client (centralized like UsersPage/BlipPost) ---
const API_BASE_URL = (import.meta.env?.VITE_API_BLIP_FEED || '').replace(/\/+$/, '')

const http = axios.create({
  baseURL: API_BASE_URL || undefined, // falls back to relative if unset
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
})

// RU from header (Cosmos)
const parseRu = (res) => {
  const h = res?.headers?.['x-ms-request-charge']
  const ru = h ? parseFloat(Array.isArray(h) ? h[0] : h) : 0
  return Number.isFinite(ru) ? ru : 0
}

// Uniform error shape
const getErr = (err) =>
  err?.response?.data?.error ||
  err?.response?.data?.message ||
  (typeof err?.response?.data === 'string' ? err.response.data : '') ||
  err.message ||
  'Request failed'

// Minimal API wrapper
const api = {
  // GET /blips?userId&cursor&pageSize
  list: async ({ userId, pageSize = 10, cursor } = {}) => {
    const res = await http.get('/blips', { params: { userId, pageSize, cursor } })
    // prefer header RU; fall back to body.ru if service returns it
    const ru = parseRu(res) || Number(res.data?.ru) || 0
    const items = Array.isArray(res.data?.items) ? res.data.items : []
    const nextCursor = res.data?.continuationToken || res.data?.next || null
    return { items, nextCursor, ru }
  },
}

// --- helpers ---
const formatDate = (iso) => {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleString()
}

export default function BlipFeed({ userId, pageSize = 10 })  {
  const [feed, setFeed] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [ru, setRu] = useState(0)

  useEffect(() => {
    let mounted = true
    ;(async () => {
      try {
        setLoading(true)
        setError(null)
        const { items, ru } = await api.list({ userId, pageSize })
        if (!mounted) return
        setFeed(items)
        setRu(ru)
      } catch (e) {
        if (!mounted) return
        setError(getErr(e))
      } finally {
        if (mounted) setLoading(false)
      }
    })()
    return () => { mounted = false }
  }, [userId, pageSize])

  if (loading) {
    return (
      <div className="loading">
        <div className="spinner" aria-hidden="true"></div>
        <span className="muted">Loading feed…</span>
      </div>
    )
  }

  if (error) {
    return <div className="alert alert-error">Error loading feed: {error}</div>
  }

  if (feed.length === 0) {
    return (
      <>
        <div className="metrics"><span className="chip">Page RU: {ru.toFixed(3)}</span></div>
        <div className="empty">No items in the feed yet.</div>
      </>
    )
  }

  return (
    <>
      <div className="metrics"><span className="chip">Page RU: {ru.toFixed(3)}</span></div>
      <ul className="feed-list">
        {feed.map((item) => {
          const content = item.text?.trim() || '— no text —'
          const initials = (item.userId ?? '?').toString().slice(0, 2).toUpperCase()
          return (
            <li key={`${item.id}-${item.createdAt}`} className="feed-item">
              <div className="avatar" aria-hidden="true">{initials}</div>
              <div className="feed-content">
                <div className="feed-meta">
                  <span className="feed-user">User {item.userId}</span>
                  <span className="dot">•</span>
                  <time className="muted" dateTime={item.createdAt}>{formatDate(item.createdAt)}</time>
                  <span className="chip">#{item.id}</span>
                </div>
                <p className="feed-text">{content}</p>
              </div>
            </li>
          )
        })}
      </ul>
    </>
  )
}
