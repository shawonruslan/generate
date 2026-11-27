// Runs at document_start on stableaudio.com and authkit.app inside GeckoView.
// Captures WorkOS access_token / refresh_token / client_id via Firefox
// wrappedJSObject + exportFunction (CSP-proof) and drives sign-up + OTP.
(() => {
  if (window.top !== window.self) return;

  const port = browser.runtime.connect({ name: "ais-sa" });
  let autoCfg = null; // { email, password, otp }
  let otpRequested = false;
  let signupClickedAt = 0;
  let emailSubmittedAt = 0;
  let passSubmittedAt = 0;
  let otpSubmittedAt = 0;
  let termsClickedAt = 0;
  let tokenSent = false;
  let lastClientId = "client_01M5FKRSSZMYNTGJZ7SF9WXKH6";

  function emitToken(accessToken, refreshToken, clientId) {
    if ((!accessToken && !refreshToken) || tokenSent) return;
    tokenSent = true;
    try {
      port.postMessage({
        type: "sa_token",
        accessToken: accessToken ? String(accessToken) : "",
        refreshToken: refreshToken ? String(refreshToken) : "",
        clientId: clientId ? String(clientId) : lastClientId,
      });
    } catch (e) {}
  }

  function extractBearer(headers) {
    if (!headers) return "";
    try {
      if (typeof headers.get === "function") {
        const v = headers.get("authorization") || headers.get("Authorization") || "";
        if (v.startsWith("Bearer ")) return v.slice(7).trim();
      }
      if (Array.isArray(headers)) {
        for (const pair of headers) {
          if (pair && String(pair[0]).toLowerCase() === "authorization") {
            const v = String(pair[1] || "");
            if (v.startsWith("Bearer ")) return v.slice(7).trim();
          }
        }
      }
      if (typeof headers === "object") {
        for (const k of Object.keys(headers)) {
          if (k.toLowerCase() === "authorization") {
            const v = String(headers[k] || "");
            if (v.startsWith("Bearer ")) return v.slice(7).trim();
          }
        }
      }
    } catch (e) {}
    return "";
  }

  // CSP-proof page fetch hook using Firefox's wrappedJSObject + exportFunction.
  try {
    const pageWin = window.wrappedJSObject;
    if (pageWin && typeof exportFunction === "function" && !pageWin.__aisSaHooked) {
      pageWin.__aisSaHooked = true;
      const origFetch = pageWin.fetch;
      const hookedFetch = function (input, init) {
        let url = "";
        let reqClientId = "";
        try {
          url = typeof input === "string" ? input : (input && input.url) || "";
          const hdrs = (init && init.headers) || (input && input.headers);
          const tok = extractBearer(hdrs);
          if (tok && tok.length > 40) {
            emitToken(tok, "", lastClientId);
          }
          if (url.includes("workos.com/user_management/authenticate") && init && typeof init.body === "string") {
            const b = JSON.parse(init.body);
            if (b && b.client_id) {
              reqClientId = String(b.client_id);
              lastClientId = reqClientId;
            }
          }
        } catch (e) {}

        const p = origFetch.apply(this, arguments);
        try {
          if (url.includes("/authenticate") || url.includes("/oauth/token") || url.includes("/token")) {
            Promise.resolve(p).then((res) => {
              try {
                if (!res || !res.ok) return;
                res.clone().text().then((txt) => {
                  try {
                    const j = JSON.parse(txt);
                    const tok = j && (j.access_token || j.accessToken || j.token || j.id_token || (j.data && j.data.access_token));
                    const rt = (j && j.refresh_token) || "";
                    if ((tok && typeof tok === "string" && tok.length > 40) || (rt && typeof rt === "string")) {
                      emitToken(tok || "", rt, reqClientId || lastClientId);
                    }
                  } catch (e) {}
                }).catch(() => {});
              } catch (e) {}
            }).catch(() => {});
          }
        } catch (e) {}
        return p;
      };
      pageWin.fetch = exportFunction(hookedFetch, pageWin);
    }
  } catch (e) {}

  function scanStorage() {
    if (tokenSent) return;
    if (!location.hostname.endsWith("stableaudio.com") ||
        location.hostname.startsWith("login.") ||
        location.hostname.includes("authkit.")) return;
    const scan = (st) => {
      try {
        for (let i = 0; i < st.length; i++) {
          const k = st.key(i) || "";
          const v = (st.getItem(k) || "").trim();
          if (/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v)) {
            return { at: v, rt: "" };
          }
          if (k.toLowerCase().includes("workos") && k.toLowerCase().includes("refresh") && v.length > 12) {
            return { at: "", rt: v };
          }
          try {
            const p = JSON.parse(v);
            const t = p?.body?.access_token || p?.access_token || p?.accessToken || p?.token || p?.id_token;
            const rt = p?.body?.refresh_token || p?.refresh_token || p?.refreshToken || "";
            if ((typeof t === "string" && t.length > 40) || (typeof rt === "string" && rt.length > 12)) {
              return { at: typeof t === "string" ? t : "", rt: typeof rt === "string" ? rt : "" };
            }
          } catch (e) {}
        }
      } catch (e) {}
      return null;
    };
    const found = scan(localStorage) || scan(sessionStorage);
    if (found && found.at) {
      emitToken(found.at, found.rt, lastClientId);
    } else if (found && found.rt && !location.search.includes("code=")) {
      emitToken("", found.rt, lastClientId);
    }
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

    if (host.endsWith("stableaudio.com") && !host.startsWith("login.") && !host.includes("authkit.")) {
      if (url.includes("/terms") || url.includes("onboarding")) {
        if (Date.now() - termsClickedAt < 5000) return;
        termsClickedAt = Date.now();
        document.querySelectorAll('input[type="checkbox"], [role="checkbox"]').forEach((el) => {
          if (!(el.checked === true || el.getAttribute("aria-checked") === "true")) el.click();
        });
        const btn = [...document.querySelectorAll("button")].find((b) =>
          /accept|agree|continue|get started/i.test(b.innerText || "")
        ) || document.querySelector('button[type="submit"]');
        if (btn) btn.click();
        return;
      }
      if (url.includes("code=") || url.includes("workspace-next")) return;
      if (Date.now() - signupClickedAt < 8000) return;
      const btns = [...document.querySelectorAll("button, a")].filter((el) =>
        /^\s*(start\s*free|sign\s*up)\s*$/i.test(el.innerText || el.textContent || "")
      );
      const visSignup = btns.find((el) => el.offsetParent !== null);
      if (visSignup) {
        signupClickedAt = Date.now();
        visSignup.click();
        return;
      }
      // Mobile fallback: open hamburger menu if desktop "Start free" is hidden
      const menuBtn = document.querySelector('button[aria-label="Open menu"]');
      if (menuBtn && menuBtn.offsetParent !== null && menuBtn.getAttribute("aria-expanded") !== "true") {
        menuBtn.click();
        setTimeout(() => {
          const mBtns = [...document.querySelectorAll("button, a")].filter((el) =>
            /^\s*(start\s*free|sign\s*up)\s*$/i.test(el.innerText || el.textContent || "")
          );
          const mVis = mBtns.find((el) => el.offsetParent !== null) || mBtns[0];
          if (mVis) {
            signupClickedAt = Date.now();
            mVis.click();
          }
        }, 350);
      }
      return;
    }

    // AuthKit / login page
    const emailEl = document.querySelector('input[name="email"], input[type="email"], input[autocomplete="email"]');
    const passEl = document.querySelector('input[name="password"], input[type="password"]');
    const otpEl = document.querySelector('input[name="code"], input[autocomplete="one-time-code"], input[data-input-otp], input[maxlength="1"], input[maxlength="6"]');

    if (otpEl || url.includes("email-verification") || url.includes("verify")) {
      if (autoCfg.otp) {
        if (Date.now() - otpSubmittedAt < 6000) return;
        otpSubmittedAt = Date.now();
        const code = autoCfg.otp;
        const all = [...document.querySelectorAll("input")].filter((el) => {
          const t = (el.getAttribute("type") || "").toLowerCase();
          return t !== "hidden" && t !== "checkbox" && t !== "radio";
        });
        if (all.length === 6) {
          for (let i = 0; i < 6; i++) setVal(all[i], code[i]);
        }
        const single = document.querySelector('input[autocomplete="one-time-code"], input[name="code"], input[data-input-otp], input[inputmode="numeric"]') || (all.length === 1 ? all[0] : otpEl);
        if (single) setVal(single, code);
        const pasteTarget = single || all[0] || document.querySelector("[data-input-otp-container], form");
        if (pasteTarget) {
          try {
            const dt = new DataTransfer();
            dt.setData("text/plain", code);
            pasteTarget.dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
          } catch (e) {}
        }
        setTimeout(() => {
          const btn = document.querySelector('button[type="submit"], button.ak-PrimaryButton') ||
            [...document.querySelectorAll("button")].find((b) => /verify|continue|confirm|submit/i.test(b.innerText || ""));
          if (btn) btn.click();
          else {
            const f = document.querySelector("form");
            if (f) {
              if (typeof f.requestSubmit === "function") f.requestSubmit();
              else f.submit();
            }
          }
        }, 400);
      } else if (!otpRequested) {
        otpRequested = true;
        port.postMessage({ type: "sa_need_otp" });
      }
      return;
    }

    if (passEl && passEl.offsetParent !== null) {
      if (Date.now() - passSubmittedAt < 6000) return;
      passSubmittedAt = Date.now();
      if (!passEl.value) setVal(passEl, autoCfg.password);
      setTimeout(() => {
        const btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
        if (btn) btn.click();
      }, 350);
      return;
    }

    if (emailEl && emailEl.offsetParent !== null) {
      if (Date.now() - emailSubmittedAt < 6000) return;
      emailSubmittedAt = Date.now();
      const fn = document.querySelector('input[name="first_name"], input[name="firstName"]');
      const ln = document.querySelector('input[name="last_name"], input[name="lastName"]');
      if (fn && !fn.value) setVal(fn, "Alex");
      if (ln && !ln.value) setVal(ln, "Carter");
      if (!emailEl.value) setVal(emailEl, autoCfg.email);
      setTimeout(() => {
        const btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
        if (btn) btn.click();
      }, 350);
    }
  }

  port.onMessage.addListener((m) => {
    if (!m) return;
    if (m.type === "sa_auto" && m.email) {
      tokenSent = false;
      otpRequested = false;
      signupClickedAt = 0;
      emailSubmittedAt = 0;
      passSubmittedAt = 0;
      otpSubmittedAt = 0;
      termsClickedAt = 0;
      autoCfg = { email: m.email, password: m.password || "", otp: m.otp || "" };
      stepAuto();
    } else if (m.type === "sa_otp" && m.otp && autoCfg) {
      autoCfg.otp = m.otp;
      otpSubmittedAt = 0;
      stepAuto();
    }
  });

  setInterval(() => {
    scanStorage();
    if (autoCfg) stepAuto();
  }, 900);
})();
