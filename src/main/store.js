// Small JSON store in %APPDATA%/Wafid Desktop/store.json (debounced writes).
const fs = require("fs");
const path = require("path");

class Store {
  constructor(dir, defaults) {
    this.file = path.join(dir, "store.json");
    this.data = JSON.parse(JSON.stringify(defaults));
    try {
      const saved = JSON.parse(fs.readFileSync(this.file, "utf8"));
      for (const k of Object.keys(saved)) {
        this.data[k] = (saved[k] && typeof saved[k] === "object" && !Array.isArray(saved[k]) && this.data[k] && !Array.isArray(this.data[k]))
          ? Object.assign({}, this.data[k], saved[k]) : saved[k];
      }
    } catch (e) { /* first run */ }
    this.timer = null;
  }
  get(k) { return this.data[k]; }
  set(k, v) { this.data[k] = v; this.save(); }
  save() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), 300);
  }
  flush() {
    clearTimeout(this.timer);
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true });
      const tmp = this.file + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(this.data, null, 1));
      fs.renameSync(tmp, this.file);
    } catch (e) { console.error("store write failed", e); }
  }
}
module.exports = Store;
