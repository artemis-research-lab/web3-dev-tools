* text=auto
*.ps1 text eol=crlf
*.py text eol=lf
*.md text eol=lf
*.sh text eol=lf
# tools/ holds the checksummed bundle copy: keep its bytes unchanged.
tools/** -text
