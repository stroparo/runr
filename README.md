# Runr

Execution tool to run routines passed in as arguments.

By default it will fetch available routines from stroparo/dotfiles otherwise pass in the REPOS global exported, or -r "repos list one per line" to override that default with other routines.

## Requirements

* Call the ```./entry.sh``` script only from inside the runr directory i.e. first ```cd /path/to/runr``` (automatically done by the automated remote provisioning below)

---

## Basic usage

The main script is ```entry.sh``` at the root directory. Enter the runr directory before calling it -- this is VERY IMPORTANT -- otherwise it will provision itself to ```$HOME/runr-master``` and cd into it by itself before starting.

Please beware of the -r REPOS and the REPOS global variable as explained previously. These repositories are the providers of routines for runr to execute.

#### Recipes

After the options you might specify arguments. These are a list of recipes to be executed which have being archived/cloned from the REPOS global (or the list passed in via ther -r REPOS option), one repo per line.

Recipes are scripts and they must be inside directories within each repository in REPOS i.e. any other directory level (root or descendant) will be ignored.

The arguments might omit the ```.sh``` extension and those recipes will still be called correctly.

---

## Automated Remote Provisioning

The script has self-provisioning capabilities so you can skip downloading and setting it up by calling this command:

```bash
bash -c "$(curl -LSf "https://bitbucket.org/stroparo/runr/raw/master/entry.sh" \
  || curl -LSf "https://raw.githubusercontent.com/stroparo/runr/master/entry.sh")" \
  entry.sh # [routine1 [routine2 ...]]
```

---

## Troubleshoot: curl program not available

If you do not have curl, substitute ```wget -O -``` for ```curl [options]``` in the command.

---

## Troubleshoot certificate issues in restricted networks

In case you are inside a restricted network and certificate verification fails for the curl download then try using curl's -k option which bypasses SSL (security) check -- obviously you know what you are doing and hold yourself entirely responsible for such an act.

Download & comprehensive setup:

```bash
curl -LSf -k -o ~/.runr.zip "https://github.com/stroparo/runr/archive/master.zip" \
  && unzip -o ~/.runr.zip -d "$HOME" \
  && cd "$HOME"/runr-master \
  && ./entry.sh # [routine1 [routine2 ...]]
```

---

