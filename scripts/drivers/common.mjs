import os from "node:os";
import path from "node:path";

export const KEY_ALIASES = {
  return: "enter",
  esc: "escape",
  del: "delete",
  bs: "backspace",
  pgup: "pageup",
  pgdn: "pagedown",
  pgdown: "pagedown",
  arrowup: "up",
  arrowdown: "down",
  arrowleft: "left",
  arrowright: "right",
  control: "ctrl",
  option: "alt",
  command: "cmd",
  super: "meta",
  win: "meta",
  windows: "meta",
  caps: "capslock",
  volup: "volumeup",
  voldown: "volumedown",
};

export const INTERACTIVE_ROLES = new Set([
  "button",
  "axbutton",
  "checkbox",
  "axcheckbox",
  "radiobutton",
  "axradiobutton",
  "textfield",
  "axtextfield",
  "textarea",
  "axtextarea",
  "edit",
  "document",
  "combobox",
  "axcombobox",
  "popupbutton",
  "axpopupbutton",
  "menubutton",
  "axmenubutton",
  "menuitem",
  "axmenuitem",
  "tab",
  "tabitem",
  "axradiogroup",
  "link",
  "axlink",
  "hyperlink",
  "slider",
  "axslider",
  "switch",
  "toggle",
  "listitem",
  "treeitem",
  "axrow",
  "axcell",
]);

export function resolveDataDir() {
  return (
    process.env.PLUGIN_DATA ||
    process.env.COMPUTER_USE_DATA_DIR ||
    path.join(os.tmpdir(), "agy-computer-use-data")
  );
}

export function resolvePluginRoot() {
  return (
    process.env.PLUGIN_ROOT ||
    path.resolve(path.dirname(new URL(import.meta.url).pathname), "..", "..")
  );
}

export function normalizeKeyName(key) {
  if (typeof key !== "string" || !key.trim()) {
    throw new Error("Key must be a non-empty string.");
  }
  const lower = key.trim().toLowerCase();
  return KEY_ALIASES[lower] || lower;
}

export function normalizeModifiers(modifiers = [], platform = process.platform) {
  if (!Array.isArray(modifiers)) {
    throw new Error("Modifiers must be an array of strings.");
  }
  const normalized = [];
  for (const raw of modifiers) {
    if (typeof raw !== "string" || !raw.trim()) continue;
    let mod = raw.trim().toLowerCase();
    if (mod === "primary") {
      mod = platform === "darwin" ? "cmd" : "ctrl";
    } else {
      mod = KEY_ALIASES[mod] || mod;
    }
    if (mod === "meta") {
      mod = platform === "darwin" ? "cmd" : "win";
    }
    if (!["shift", "ctrl", "alt", "cmd", "win"].includes(mod)) {
      throw new Error(`Unsupported modifier key: "${raw}"`);
    }
    if (!normalized.includes(mod)) {
      normalized.push(mod);
    }
  }
  return normalized;
}

export function normalizeHotkey(keys = [], platform = process.platform) {
  if (!Array.isArray(keys) || keys.length === 0) {
    throw new Error("hotkey requires a non-empty array of keys.");
  }
  const modifierSet = new Set(["primary", "shift", "ctrl", "control", "alt", "option", "cmd", "command", "meta", "win", "windows", "super"]);
  const modifiers = [];
  const mainKeys = [];

  for (const k of keys) {
    const lower = String(k).trim().toLowerCase();
    if (modifierSet.has(lower)) {
      modifiers.push(...normalizeModifiers([lower], platform));
    } else {
      mainKeys.push(normalizeKeyName(lower));
    }
  }

  return {
    modifiers: [...new Set(modifiers)],
    key: mainKeys[mainKeys.length - 1] || null,
    extraKeys: mainKeys.slice(0, -1),
  };
}

export function isInteractiveRole(role) {
  if (!role) return false;
  const cleaned = String(role).toLowerCase().replace(/[^a-z]/g, "");
  return INTERACTIVE_ROLES.has(cleaned);
}

export function filterUiElements(elements, { query, role, limit = 25 } = {}) {
  const q = query ? String(query).trim().toLowerCase() : null;
  const r = role ? String(role).trim().toLowerCase().replace(/[^a-z]/g, "") : null;

  const matches = [];
  for (const el of elements) {
    if (r) {
      const elRole = String(el.role || "").toLowerCase().replace(/[^a-z]/g, "");
      if (!elRole.includes(r)) continue;
    }
    if (q) {
      const haystack = [el.title, el.label, el.value, el.identifier, el.description]
        .filter((v) => typeof v === "string" && v.length > 0)
        .join(" ")
        .toLowerCase();
      if (!haystack.includes(q)) continue;
    }
    matches.push(el);
    if (matches.length >= limit) break;
  }
  return matches;
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
