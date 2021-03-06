#!/usr/bin/env bash
#set -e

export ROOT=$(pwd)

git_clone () {
    git clone "${1}" "${2}" #> /dev/null 2>&1
    if [ "$?" != "0" ]; then
        return 1
    fi
    return 0
}

git_update_repos () {
    repos=$1
    version=$2
    folder=$3
    isFromJson=$4
    echo "node $ROOT/sync.js create-component.json $repos $version $isFromJson $folder"
    node $ROOT/sync.js create-component.json "$repos" "$version" "$isFromJson" "$folder" 
    if [ "$?" != "0" ]; then
        return 1
    fi

    #AU
    git config --global user.email "${GIT_EMAIL}"
    git config --global user.name "${GIT_NAME}"
    git config --global push.default simple
    git config credential.helper "store --file=.git/credential"
    echo "https://${GH_TOKEN}:@github.com" > .git/credential

    git add -A -f

    if [ "$isFromJson" = "true" ]; then
        git commit -m "based on https://github.com/fis-components/components/blob/master/packages/${folder}${repos}.json" -a
    else
        git commit -m "based on https://github.com/fis-components/components/blob/master/modules/${folder}${repos}.js" -a
    fi

    
    git push origin master
    git tag -a "$version" -m "create tag $version"
    git push --tags

    bos_sync $repos $version
}

bos_sync () {
    echo "BOS Sync ${1}@${2}"
    bash $ROOT/bosSync.sh $1 $2
    if [ "$?" != "0" ]; then
        exit 1
    fi
}

save_hash() {
    echo "Save hash  ${1}@${2}@${3}"
    bash $ROOT/saveHash.sh $1 $2 $3
    if [ "$?" != "0" ]; then
        exit 1
    fi
}

export -f git_clone
export -f git_update_repos
export -f bos_sync
export -f save_hash

sync () {
    new=$1
    repos=$2
    build=$3
    version=$4
    build_dest=$5
    tag=$6
    rebuild=$7
    folder=$8
    isFromJson=$9

    echo "Folder is $folder"
    dest="$ROOT/_$new"

    echo "=SYNC ${new} from ${repos}, version: ${version}"

    if [ -d "_${new}" ]; then
        rm -rf "_${new}"
        echo "=LOCAL rm -rf _${new}"
    fi

    git_clone "https://github.com/fis-components/${new}" "_${new}"

    if [ "$?" != "0" ]; then
        # new origin
        node $ROOT/sync.js create-repos "${new}" "${GH_TOKEN}" "${repos}" "$folder" "$isFromJson"
        if [ "$?" != "0" ]; then
            exit 1
        fi
        git_clone "https://github.com/fis-components/${new}" "_${new}"
        if [ "$?" != "0" ]; then
            exit 1
        fi
    else
        cd "_${new}"
        git pull --all
        found=$(git tag | grep $version)

        if [ "$found" != "" ]; then
            if [ "$rebuild" = "true" ]; then
                echo "= Tag $version already exists, now deleting..."

                #AU
                git config --global user.email "${GIT_EMAIL}"
                git config --global user.name "${GIT_NAME}"
                git config --global push.default simple
                git config credential.helper "store --file=.git/credential"
                echo "https://${GH_TOKEN}:@github.com" > .git/credential

                git tag -d "$version"
                git push origin :refs/tags/$version

                echo "= Clean all files"
                git ls-files | xargs git rm
                git commit -am "rm all files"
                git push
            else
                echo "=TAG tag $version exists. Skiped!"
                exit 0
            fi
        fi

        cd $ROOT
    fi

    if [ -d $new ]; then
        rm -rf $new
        echo "=LOCAL rm -rf $new"
    fi

    git_clone $repos $new

    if [ "$?" = "0" ]; then

        cd $new

        git checkout $tag

        if [ "$?" != "0" ]; then
            echo "=GIT: git checkout $tag fail."
            exit 1
        fi

        # run build
        if [ "$build" != "" ]; then
            echo  '=BUILD '$new
            touch package.json
            eval $build || ('=BUILD build fail.' 2>&1 || exit 1)
        fi

        # if [ -d "$build_dest" ]; then
        #     cp -rf "./${build_dest}" "$dest"
        # fi

        # if [ -d "./dist" ]; then
        #     cp -rf "./dist" "$dest"
        # fi
    else 
        if [ "$build" != "" ]; then
            mkdir -p $new
            cd $new
            touch package.json
            echo  '=BUILD '$new
            eval $build || ('=BUILD build fail.' 2>&1 || exit 1)
        fi
    fi

    node $ROOT/sync.js move "$new" "$version" "$(pwd)" "$dest" "$folder" "$isFromJson"

    node $ROOT/sync.js convert "$new" "$version" "$dest" "$folder" "$isFromJson"

    if [ "$?" != "0" ]; then
        echo '=ROADMAP move fail'
        exit 1
    fi

    cd "$dest"
    echo "=CD $dest"

    git_update_repos "$new" "$version" "$folder" "$isFromJson"

    if [ "$isFromJson" = "true" ]; then
        save_hash "$new" "$version" "$folder"
    fi

    cd $ROOT
}

export -f sync

main () {
    echo '#START build.sh'
    sync "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
    echo '#END build.sh'
}

main "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
