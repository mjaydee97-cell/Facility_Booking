const { badRequest } = require('../errors');

// Parses req[source] with a zod schema and replaces it with the parsed value.
const validate = (schema, source = 'body') => (req, _res, next) => {
  const result = schema.safeParse(req[source]);
  if (!result.success) {
    const details = result.error.issues.map((i) => ({ field: i.path.join('.'), message: i.message }));
    return next(badRequest('Validation failed', details));
  }
  req[source === 'query' ? 'validQuery' : source] = result.data;
  next();
};

module.exports = { validate };
