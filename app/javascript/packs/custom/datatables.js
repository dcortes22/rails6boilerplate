require("datatables.net")
require('datatables.net-bs4')
require("datatables.net-bs4/css/dataTables.bootstrap4.min.css")

var dataTable = null;

document.addEventListener("turbolinks:load", () => {
  if (dataTable == null && $('.dataTable').length !== 0) {
    dataTable = $('.dataTable').DataTable({
      pageLength: 50
    });
  }
});

document.addEventListener("turbolinks:before-cache", () => {
  if (dataTable != null) {
    dataTable.destroy();
    dataTable = null;
  }
});