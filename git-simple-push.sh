#!/bin/sh -
#@ git-simple-push.sh - synchronize a bunch of local repos with their remotes.
#@ ..In case any local branch has a different SHA1 as the remote ref this
#@ brute simple thing will invoke "git push -f REMOTE".
#@ TODO do a real version compare, like that we could manage tags, too!
#
# Public Domain

cd "${HOME}/arena/code" || exit 42
REPOS="s-cacert.update_bomb_git-no_reduce\
    s-ctext.git\
    s-musicbox.git\
    s-nail.git\
    s-roff.git\
    s-symobj.git\
    s-toolbox.git\
    s-web42.git"

for d in ${REPOS}; do
  (
  echo "Checking ${d}"
  cd "${d}" || exit 1
  APO=\'
  git show-ref |
  awk '
    {
      if ($2 ~ /^refs\/remotes/) {
        repo = substr($2, 14)
        i = index(repo, "/")
        if (i == 0) {
          print "I don'${APO}'t understand \"" $2 "\"" >> "/dev/stderr"
          next
        }

        br = substr(repo, i + 1)
        if (length(br) == 0) {
          print "I can'${APO}'t parse branch of \"" $2 "\"" >> "/dev/stderr"
          next
        }

        --i
        repo = substr(repo, 1, i)
        if (i == 0 || length(repo) == 0) {
          print "I can'${APO}'t parse repo of \"" $2 "\"" >> "/dev/stderr"
          next
        }

        rembr[repo br] = br
        remsha[repo br] = $1
        remrepo[repo] = repo
      } else if ($2 ~ /^refs\/heads/) {
        br = substr($2, 12)
        locbr[br] = br
        locsha[br] = $1
      }
    }
    END {
      for (repo in remrepo) {
        for (br in locbr) {
          # We ignore non-existent branches
          if (!rembr[repo br])
            continue
          if (locsha[br] != remsha[repo br]) {
            print "++ Pushing to \"" repo "\" (at least \"" br "\" differs)!"
            system("git push -f " repo)
            break
          }
        }
      }
    }
  '
  )
done

# s-it2-mode
