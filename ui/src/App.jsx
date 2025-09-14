// src/App.jsx
import { useState, useEffect } from 'react'
import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom'
import BlipFeed from './components/blipFeed'
import BlipPost from './components/blipPost'
import UsersPage from './components/UsersPage'
import GraphPage from './components/GraphPage'

function HomeScreen({ onPosted, feedVersion, userId }) {
  return (
    <div className="grid">
      <section className="col col--compose">
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Compose</h2>
            <p className="card-subtitle">Share a quick update.</p>
          </div>
          <div className="card-body">
            <BlipPost userId={userId} onPosted={onPosted} />
          </div>
        </div>
      </section>

      <section className="col col--feed">
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Recent Blips</h2>
            <p className="card-subtitle">Latest posts, newest first.</p>
          </div>
          <div className="card-body">
            <BlipFeed key={feedVersion} userId={userId} />
          </div>
        </div>
      </section>
    </div>
  )
}

export default function App() {
  // Persist the selection so reloads keep it
  const [userId, setUserId] = useState(() => localStorage.getItem('blips:userId') || '')
  useEffect(() => { localStorage.setItem('blips:userId', userId || '') }, [userId])

  const [feedVersion, setFeedVersion] = useState(0)
  const handlePosted = () => setFeedVersion(v => v + 1)

  return (
    <BrowserRouter>
      <div className="app-shell">
        <header className="site-header">
          <div className="container" style={{ gap: 16 }}>
            <h1 className="brand">Blips</h1>
            <nav className="nav">
              <NavLink className="nav-link" to="/">Home</NavLink>
              <NavLink className="nav-link" to="/users">Users</NavLink>
              <NavLink className="nav-link" to="/graph">Graph</NavLink>
            </nav>

            {/* Active user control */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginLeft: 'auto' }}>
              <label htmlFor="active-user-id" className="label" style={{ margin: 0 }}>User ID</label>
              <input
                id="active-user-id"
                className="input"
                type="text"
                placeholder="e.g. acorn or GUID"
                value={userId}
                onChange={e => setUserId(e.target.value)}
                style={{ width: 240 }}
              />
            </div>
          </div>
        </header>

        <main className="container">
          <Routes>
            <Route path="/" element={<HomeScreen userId={userId} onPosted={handlePosted} feedVersion={feedVersion} />} />
            <Route path="/users" element={<UsersPage />} />
            <Route path="/graph" element={<GraphPage />} />
          </Routes>
        </main>

        <footer className="site-footer">
          <div className="container">
            <small>© {new Date().getFullYear()} Blips — All rights reserved.</small>
          </div>
        </footer>
      </div>
    </BrowserRouter>
  )
}
