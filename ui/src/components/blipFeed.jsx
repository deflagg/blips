// src/components/blipFeed.jsx
import { useState, useEffect } from 'react'

function formatDate(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleString()
}

function BlipFeed() {
  const [feed, setFeed] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [ru, setRu] = useState(0)

  useEffect(() => {
    const fetchFeed = async () => {
      try {
        const response = await fetch('https://blipfeed.blips.service/blips?userId=1&pageSize=10')
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        const data = await response.json()
        setFeed(Array.isArray(data.items) ? data.items : [])
        setRu(Number(data.ru) || 0)
      } catch (err) {
        setError(err.message)
      } finally {
        setLoading(false)
      }
    }
    fetchFeed()
  }, [])

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

export default BlipFeed
