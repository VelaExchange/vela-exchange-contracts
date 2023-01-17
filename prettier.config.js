module.exports = {
  "overrides": [{
    "files": "*.sol", "options": {
        "printWidth": 80, // Please uncomment this after the end of the audit. The code looks nice at 120 width.
        //    The default (which we now have) is 80, and it makes code hard to read.
        //    120 - is the most widely accepted standard across different languages.
        //    If we uncomment this now, we'll have too many diff conflicts.
        // "printWidth": 120,
        "tabWidth": 4, "useTabs": false, "singleQuote": false, "bracketSpacing": false
    }
  }]
};