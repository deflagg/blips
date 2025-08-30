// src/App.jsx
import { useState } from 'react'
import BlipFeed from './components/blipFeed'
import BlipPost from './components/blipPost'

function App() {
  const [feedVersion, setFeedVersion] = useState(0);

  const handlePosted = () => {
    // Force BlipFeed to re-fetch after a successful post
    setFeedVersion(v => v + 1);
  };

  return (
    <div className="app-shell">
      <header className="site-header">
        <div className="container">
          <h1 className="brand">Blips</h1>
          <nav className="nav">
            <a className="nav-link" href="#" aria-disabled="true">Home</a>
            <a className="nav-link" href="#" aria-disabled="true">Activity</a>
            <a className="nav-link" href="#" aria-disabled="true">Settings</a>
          </nav>
        </div>
      </header>

      <main className="container">
        <div className="grid">
          <section className="col col--compose">
            <div className="card">
              <div className="card-header">
                <h2 className="card-title">Compose</h2>
                <p className="card-subtitle">Share a quick update.</p>
              </div>
              <div className="card-body">
                <BlipPost onPosted={handlePosted} />
              </div>
            </div>
          </section>

          <section className="col col--feed">
            <div className="card">
              <div className="card-header">
                <h2 className="card-title">Recent Blips New 2</h2>
                <p className="card-subtitle">Latest posts, newest first.</p>
              </div>
              <div className="card-body">
                <BlipFeed key={feedVersion} />
              </div>
            </div>
          </section>
        </div>
      </main>

      <footer className="site-footer">
        <div className="container">
          <small>© {new Date().getFullYear()} Blips — All rights reserved.</small>
        </div>
      </footer>
    </div>
  )
}

export default App
