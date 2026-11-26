// Runs at document_start on stableaudio.com and authkit.app inside GeckoView.
// Captures WorkOS access_token / refresh_token / client_id and optionally
// drives the automated sign-up + OTP verification flow.
(() => {
  if (window.top !== window.self) return;

  const port = browser.runtime.connect({ name: "ais-sa" });
  let autoCfg = null; // { email, password, otp }
  let otpRequested = false;
  let tokenSent = false;

  function emitToken(accessToken, refreshToken, clientId) {
    if (!accessToken || tokenSent) return;
    tokenSent = true;
    try {
      port.postMessage({
        type: "sa_token",
        accessToken: String(accessToken),
        refreshToken: refreshToken ? String(refreshToken) : "",
        clientId: clientId ? String(clientId) : "",
      });
    } catch (e) {}
  }

  // Inject page-context fetch hook to capture WorkOS /authenticate JSON.
  try {
    const s = document.createElement("script");
    s.textContent = `(() => {
      if (window.__aisSaHooked) return;
      window.__aisSaHooked = true;
      const origFetch = window.fetch;
      window.fetch = async function(...args) {
        let reqClientId = "";
        try {
          const url = typeof args[0] === "string" ? args[0] : (args[0] && args[0].url) || "";
          const init = args[1] || {};
          if (url.includes("workos.com/user_management/authenticate") && typeof init.body === "string") {
            const b = JSON.parse(init.body);
            if (b && b.client_id) reqClientId = b.client_id;
          }
        } catch (e) {}
        const res = await origFetch.apply(this, args);
        try {
          const url = res.url || "";
          if (res.ok && (url.includes("/authenticate") || url.includes("/oauth/token") || url.includes("/token"))) {
            const clone = res.clone();
            clone.json().then((j) => {
              const tok = j && (j.access_token || j.accessToken || j.token || j.id_token || (j.data && j.data.access_token));
              if (tok && typeof tok === "string" && tok.length > 40) {
                window.postMessage({
                  __ais_sa: true,
                  accessToken: tok,
                  refreshToken: (j && j.refresh_token) || "",
                  clientId: reqClientId,
                }, "*");
              }
            }).catch(() => {});
          }
        } catch (e) {}
        return res;
      };
    })();`;
    (document.head || document.documentElement).appendChild(s);
    s.remove();
  } catch (e) {}

  window.addEventListener("message", (ev) => {
    if (ev.source !== window || !ev.data || !ev.data.__ais_sa) return;
    emitToken(ev.data.accessToken, ev.data.refreshToken, ev.data.clientId);
  });

  function scanStorage() {
    if (tokenSent) return;
    if (!location.hostname.endsWith("stableaudio.com") ||
        location.hostname.startsWith("login.") ||
        location.hostname.includes("authkit.")) return;
    const scan = (st) => {
      try {
        for (let i = 0; i < st.length; i++) {
          const v = (st.getItem(st.key(i)) || "").trim();
          if (/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v)) return v;
          try {
            const p = JSON.parse(v);
            const t = p?.body?.access_token || p?.access_token || p?.accessToken || p?.token || p?.id_token;
            if (typeof t === "string" && t.length > 40) return t;
          } catch (e) {}
        }
      } catch (e) {}
      return null;
    };
    const tok = scan(localStorage) || scan(sessionStorage);
    if (tok) emitToken(tok, "", "");
  }

  function setVal(el, val) {
    if (!el) return;
    el.focus();
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
    if (setter) setter.call(el, val);
    else el.value = val;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function stepAuto() {
    if (!autoCfg || tokenSent) return;
    const host = location.hostname;
    const url = location.href;

    if (host.endsWith("stableaudio.com") && !host.startsWith("login.")) {
      if (url.includes("/terms") || url.includes("onboarding")) {
        document.querySelectorAll('input[type="checkbox"], [role="checkbox"]').forEach((el) => {
          if (!(el.checked === true || el.getAttribute("aria-checked") === "true")) el.click();
        });
        const btn = [...document.querySelectorAll("button")].find((b) =>
          /accept|agree|continue|get started/i.test(b.innerText || "")
        ) || document.querySelector('button[type="submit"]');
        if (btn) btn.click();
        return;
      }
      const signup = [...document.querySelectorAll("button, a")].find((el) =>
        /^\s*sign\s*up\s*$/i.test(el.innerText || el.textContent || "")
      );
      if (signup) signup.click();
      return;
    }

    // AuthKit / login page
    const emailEl = document.querySelector('input[name="email"], input[type="email"], input[autocomplete="email"]');
    const passEl = document.querySelector('input[name="password"], input[type="password"]');
    const otpEl = document.querySelector('input[name="code"], input[autocomplete="one-time-code"], input[maxlength="1"], input[maxlength="6"]');

    if (otpEl || url.includes("email-verification") || url.includes("verify")) {
      if (autoCfg.otp) {
        const code = autoCfg.otp;
        const all = [...document.querySelectorAll("input")].filter((el) => {
          const t = (el.getAttribute("type") || "").toLowerCase();
          return t !== "hidden" && t !== "checkbox" && t !== "radio";
        });
        if (all.length === 6) {
          for (let i = 0; i < 6; i++) setVal(all[i], code[i]);
        } else if (otpEl) {
          setVal(otpEl, code);
        }
        const btn = document.querySelector('button[type="submit"], button.ak-PrimaryButton');
        if (btn) btn.click();
        autoCfg.otp = "";
      } else if (!otpRequested) {
        otpRequested = true;
        port.postMessage({ type: "sa_need_otp" });
      }
      return;
    }

    if (passEl && passEl.offsetParent !== null && !passEl.value) {
      setVal(passEl, autoCfg.password);
      setTimeout(() => {
        const btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
        if (btn) btn.click();
      }, 300);
      return;
    }

    if (emailEl && emailEl.offsetParent !== null && !emailEl.value) {
      const fn = document.querySelector('input[name="first_name"], input[name="firstName"]');
      const ln = document.querySelector('input[name="last_name"], input[name="lastName"]');
      if (fn) setVal(fn, "Alex");
      if (ln) setVal(ln, "Carter");
      setVal(emailEl, autoCfg.email);
      setTimeout(() => {
        const btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
        if (btn) btn.click();
      }, 300);
    }
  }

  port.onMessage.addListener((m) => {
    if (!m) return;
    if (m.type === "sa_auto" && m.email) {
      autoCfg = { email: m.email, password: m.password || "", otp: m.otp || "" };
      stepAuto();
    } else if (m.type === "sa_otp" && m.otp && autoCfg) {
      autoCfg.otp = m.otp;
      stepAuto();
    }
  });

  setInterval(() => {
    scanStorage();
    if (autoCfg) stepAuto();
  }, 1000);
})();
