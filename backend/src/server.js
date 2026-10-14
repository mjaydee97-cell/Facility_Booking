const app = require('./app');
const config = require('./config');
const scheduler = require('./jobs/scheduler');

app.listen(config.port, () => {
  console.log(`Facility Booking API listening on http://localhost:${config.port}`);
  scheduler.start();
});
