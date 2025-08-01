import { useState, useEffect } from 'react';

function BlipFeed() {
  console.log('BlipFeed component is mounting/rendering');
  console.log('BlipFeed component is mounting/rendering');
  const [feed, setFeed] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchFeed = async () => {
      try {
        console.log('Fetching feed from https://blipfeed.blips.service/weatherforecast');
        const response = await fetch('https://blipfeed.blips.service/weatherforecast');
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        const data = await response.json();
        setFeed(data);
      } catch (err) {
        console.error('Error fetching feed Dennis style:', err);
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchFeed();
  }, []);

  if (loading) {
    return <div>Loading feed...</div>;
  }

  if (error) {
    return <div>Error fetching feed: {error}</div>;
  }

  return (
    <div className="news-feed">
      <h2>News Feed (Weather Forecasts)</h2>
      {feed.length === 0 ? (
        <p>No items in the feed.</p>
      ) : (
        <ul>
          {feed.map((item, index) => (
            <li key={index}>
              <strong>Date:</strong> {new Date(item.date).toLocaleDateString()} <br />
              <strong>Temperature:</strong> {item.temperatureC}°C / {item.temperatureF}°F <br />
              <strong>Summary:</strong> {item.summary}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export default BlipFeed;