# Mosaic

Test demo



## Apache2
Install by the book.

Edit **/etc/apache2/mods-available/mime.conf** and add

    AddType application/x-mpegURL .m3u8
    AddType video/MP2T .ts

Restart the server



