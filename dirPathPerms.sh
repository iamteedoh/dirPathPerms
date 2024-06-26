#!/bin/bash

# Function to wrap long lines
fold() {
  local c word wrapped
  while read -r line; do
    for word in $line; do
      c=$((c + ${#word} + 1))
      if [ $c -gt 80 ]; then
        echo "$wrapped"
        c=${#word}
        wrapped=""
      fi
      wrapped="$wrapped $word"
    done
    echo "$wrapped"
    c=0 wrapped=""
  done
}

# Function to get and validate user input for the file
get_file() {
  echo
  echo "Example file format (one absolute path per line):"
  echo
  echo "/location/of/dirname1"
  echo "/location/of/dirname2"
  echo "/location/of/filename1"
  echo "/location/of/filename2"
  echo

  fold <<< "Enter the name of the file containing the directories or files we should check.
Absolute paths are required if the script is executed from a different
location."
  echo ""
  echo -n "File path: " # Added -n to prevent new line
  read -r file_path

  while true; do
    if [[ -f "$file_path" ]]; then
      break
    else
      echo
      echo "Error: File not found. Please try again."
      echo -n "File path: " # Added -n to prevent new line
      read -r file_path
    fi
  done
}

# Function to get and validate user input for permissions
get_permissions() {
  while true; do
    echo ""
    fold <<< "Check permissions for (O)wner, (G)roup, Oth(e)r? "
    echo ""
    echo -n "Choice: " # Added -n to prevent new line
    read -r object
    case "$object" in
      [Oo]) object="u"; object_text="Owner"; break;;
      [Gg]) object="g"; object_text="Group"; break;;
      [Ee]) object="o"; object_text="Other"; break;;
      *) echo "Invalid choice. Please enter O, G, or E.";;
    esac
  done

  echo # Newline added here for separation

  while true; do
    fold <<< "Check for (R)ead, (W)rite, or e(X)ecute permissions? "
    echo ""
    echo -n "Permission: " # Added -n to prevent new line
    read -r permission
    case "$permission" in
      [Rr]) permission="r"; perm_text="read"; break;;
      [Ww]) permission="w"; perm_text="write"; break;;
      [Xx]) permission="x"; perm_text="execute"; break;;
      *) echo "Invalid choice. Please enter R, W, or X.";;
    esac
  done
}

# Get file path from user
get_file

# Get permission details from user
get_permissions

echo

# Check permissions for each path in the file
while IFS= read -r path; do
  if [[ -e "$path" ]]; then
    # Get permissions for each object
    perms=$(stat -c '%A' "$path")
    owner_perm=${perms:1:3}
    group_perm=${perms:4:3}
    other_perm=${perms:7:3}

    # Check if permission is set for the specified object
    case "$object" in
      "u")
        current_perm=$owner_perm
        ;;
      "g")
        current_perm=$group_perm
        ;;
      "o")
        current_perm=$other_perm
        ;;
    esac

    if [[ $current_perm == *"$permission"* ]]; then
      printf "\e[1;32m%-40s YES (Owner: $owner_perm, Group: $group_perm, Other: $other_perm)\e[0m\n" "$path"
    else
      printf "\e[1;31m%-40s NO $perm_text permission for $object_text (Owner: $owner_perm, Group: $group_perm, Other: $other_perm)\e[0m\n" "$path"
    fi
  else
    echo "Skipping: $path (Not a file or directory)"
  fi
done < "$file_path"

