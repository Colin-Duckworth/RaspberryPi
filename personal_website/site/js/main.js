/* main.js: the only script on the site.

   Three small jobs, each independent and each optional (the site is fully
   usable with JavaScript off):
     1. footer year
     2. header gets a background once the page has scrolled
     3. mobile menu button, and the image lightbox on the projects page */
(function () {
  'use strict';

  /* 1. Footer year. The HTML carries a static fallback. */
  var year = String(new Date().getFullYear());
  document.querySelectorAll('[data-year]').forEach(function (el) {
    el.textContent = year;
  });

  /* 2. Header background after scrolling. */
  var header = document.querySelector('.site-header');
  if (header) {
    var onScroll = function () {
      header.classList.toggle('is-scrolled', window.scrollY > 8);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  /* 3a. Mobile menu. The button owns aria-expanded; the panel is #site-menu.
         Closes on link click, on Escape (focus goes back to the button), and
         when the window is widened past the mobile breakpoint. */
  var toggle = document.querySelector('.nav-toggle');
  var menu = document.getElementById('site-menu');
  if (toggle && menu) {
    var setMenu = function (open) {
      toggle.setAttribute('aria-expanded', String(open));
      toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
      menu.classList.toggle('is-open', open);
    };
    var isOpen = function () {
      return toggle.getAttribute('aria-expanded') === 'true';
    };

    toggle.addEventListener('click', function () {
      setMenu(!isOpen());
    });

    menu.addEventListener('click', function (event) {
      if (event.target.closest('a')) {
        setMenu(false);
      }
    });

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && isOpen()) {
        setMenu(false);
        toggle.focus();
      }
    });

    var wide = window.matchMedia('(min-width: 768px)');
    var onWidthChange = function (e) {
      if (e.matches) {
        setMenu(false);
      }
    };
    if (wide.addEventListener) {
      wide.addEventListener('change', onWidthChange);
    } else if (wide.addListener) {
      wide.addListener(onWidthChange); // older Safari
    }
  }

  /* 3b. Lightbox. Built on <dialog>.showModal(), which already provides the
         backdrop, Escape to close, an inert page behind it, and keeps Tab
         inside the dialog. The links work without JS: they open the
         full-size file directly. */
  var links = document.querySelectorAll('a[data-lightbox]');
  if (links.length && typeof HTMLDialogElement === 'function') {
    var dialog = document.createElement('dialog');
    dialog.className = 'lightbox';
    dialog.setAttribute('aria-label', 'Image viewer');
    dialog.innerHTML =
      '<button type="button" class="lightbox-close">Close</button>' +
      '<figure class="lightbox-figure">' +
      '<img class="lightbox-img" alt="">' +
      '<figcaption class="lightbox-caption"></figcaption>' +
      '</figure>';
    document.body.appendChild(dialog);

    var closeButton = dialog.querySelector('.lightbox-close');
    var bigImage = dialog.querySelector('.lightbox-img');
    var caption = dialog.querySelector('.lightbox-caption');
    var opener = null;

    document.addEventListener('click', function (event) {
      var link = event.target.closest('a[data-lightbox]');
      // Leave modified clicks (new tab, etc.) to the browser.
      if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        return;
      }
      event.preventDefault();

      var thumb = link.querySelector('img');
      var figure = link.closest('figure');
      var figcaption = figure ? figure.querySelector('figcaption') : null;

      opener = link;
      bigImage.src = link.href;
      bigImage.alt = thumb ? thumb.alt : '';
      caption.textContent = figcaption ? figcaption.textContent : '';
      caption.hidden = !caption.textContent;

      dialog.showModal();
      closeButton.focus();
    });

    closeButton.addEventListener('click', function () {
      dialog.close();
    });

    // A click on the backdrop lands on the <dialog> element itself, because
    // the dialog has no padding: its content fills it completely.
    dialog.addEventListener('click', function (event) {
      if (event.target === dialog) {
        dialog.close();
      }
    });

    // Fires for every way of closing (button, Escape, backdrop).
    dialog.addEventListener('close', function () {
      bigImage.removeAttribute('src');
      if (opener) {
        opener.focus();
        opener = null;
      }
    });
  }
})();
