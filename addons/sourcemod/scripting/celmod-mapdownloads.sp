#pragma semicolon 1

#include <celmod>

#pragma newdecls required
#pragma dynamic 131072 // model texture lists

/*
 * |CelMod| Map Downloads
 *
 * Players only download a file the server has AND has put in the download table. A map's own custom textures and
 * models aren't in it unless they're packed into the .bsp, so new players saw pink textures and error models.
 *
 * On every map start this reads the map file and finds what it uses: the textures on its brushes, its sky, the
 * models of its static props and entities, and the textures of those models. Every one of them the server has as a
 * loose file (so not stock Half-Life 2 content, which is in the game's VPKs) is added to the download table.
 * What the map needs but the server doesn't have is written to data/celmod/missing_downloads/<map>.txt.
 */

#define LUMP_ENTITIES 0
#define LUMP_GAME_LUMP 35
#define LUMP_TEXDATA_STRING_DATA 43
#define GAMELUMP_STATIC_PROPS 0x73707270 // 'sprp'

ConVar g_cvEnabled;

StringMap g_smSeen;
ArrayList g_alMissing;
int g_iAdded;

public Plugin myinfo =
{
	name = "|CelMod| Map Downloads",
	author = CEL_AUTHOR,
	description = "Sends players the custom textures and models each map uses.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	g_cvEnabled = CreateConVar("cm_map_downloads", "1", "1: every map's own custom textures and models (that the server has) are sent to players.", _, true, 0.0, true, 1.0);

	g_smSeen = new StringMap();
	g_alMissing = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
}

public void OnMapStart()
{
	char sMap[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];

	if (!g_cvEnabled.BoolValue)
	{
		return;
	}

	g_smSeen.Clear();
	g_alMissing.Clear();
	g_iAdded = 0;

	GetCurrentMap(sMap, sizeof(sMap));
	FormatEx(sPath, sizeof(sPath), "maps/%s.bsp", sMap);

	File fBsp = OpenFile(sPath, "rb", true);

	if (fBsp == null)
	{
		LogError("|CelMod| Map downloads: couldn't open %s.", sPath);
		return;
	}

	int iIdent;

	fBsp.ReadInt32(iIdent);

	if (iIdent != 0x50534256) // 'VBSP'
	{
		delete fBsp;
		LogError("|CelMod| Map downloads: %s isn't a Source map file.", sPath);
		return;
	}

	ReadTextures(fBsp);
	ReadEntities(fBsp);
	ReadStaticProps(fBsp);

	delete fBsp;

	WriteMissing(sMap);

	PrintToServer("|CelMod| Map downloads: %d of %s's own files sent to players%s", g_iAdded, sMap, g_alMissing.Length > 0 ? " (some it needs aren't on the server, see data/celmod/missing_downloads)." : ".");
}

//Where a lump is in the map file (lump_t: fileofs, filelen, version, fourCC; the lumps start at byte 8).
bool GetLump(File fBsp, int iLump, int &iOffset, int &iLength)
{
	fBsp.Seek(8 + iLump * 16, SEEK_SET);

	return fBsp.ReadInt32(iOffset) && fBsp.ReadInt32(iLength) && iOffset > 0 && iLength > 0;
}

//The textures on the map's brushes: the texdata string lump is their names, one after another.
void ReadTextures(File fBsp)
{
	char sName[PLATFORM_MAX_PATH];
	int iOffset, iLength;

	if (!GetLump(fBsp, LUMP_TEXDATA_STRING_DATA, iOffset, iLength))
	{
		return;
	}

	int iPos = iOffset, iEnd = iOffset + iLength;

	while (iPos < iEnd)
	{
		fBsp.Seek(iPos, SEEK_SET);

		if (fBsp.ReadString(sName, sizeof(sName), -1) < 0)
		{
			break;
		}

		// Just past the name's end, where the next one starts.
		int iNext = iPos + strlen(sName) + 1;

		if (iNext <= iPos)
		{
			break;
		}

		iPos = iNext;

		if (sName[0] != '\0')
		{
			AddMaterial(sName);
		}
	}
}

//The entity lump is text: "key" "value" lines. Models of entities (prop_dynamic, ...) and the sky are read from it.
void ReadEntities(File fBsp)
{
	char sLine[512], sKey[64], sValue[PLATFORM_MAX_PATH];
	int iOffset, iLength;

	if (!GetLump(fBsp, LUMP_ENTITIES, iOffset, iLength))
	{
		return;
	}

	fBsp.Seek(iOffset, SEEK_SET);

	while (fBsp.Position < iOffset + iLength && fBsp.ReadLine(sLine, sizeof(sLine)))
	{
		if (!SplitKeyValue(sLine, sKey, sizeof(sKey), sValue, sizeof(sValue)))
		{
			continue;
		}

		if (StrEqual(sKey, "model", false) && StrContains(sValue, ".mdl", false) != -1)
		{
			AddModel(sValue);
		} else if (StrEqual(sKey, "skyname", false) && sValue[0] != '\0')
		{
			static const char sSides[][] = { "bk", "dn", "ft", "lf", "rt", "up" };
			char sSky[PLATFORM_MAX_PATH];

			for (int i = 0; i < sizeof(sSides); i++)
			{
				FormatEx(sSky, sizeof(sSky), "skybox/%s%s", sValue, sSides[i]);
				AddMaterial(sSky, true);

				FormatEx(sSky, sizeof(sSky), "skybox/%s_hdr%s", sValue, sSides[i]);
				AddMaterial(sSky, true);
			}
		}
	}
}

//Static props: the game lump's 'sprp' entry starts with the list of their model names (128 bytes each).
void ReadStaticProps(File fBsp)
{
	char sModel[128];
	int iOffset, iLength, iCount;

	if (!GetLump(fBsp, LUMP_GAME_LUMP, iOffset, iLength))
	{
		return;
	}

	fBsp.Seek(iOffset, SEEK_SET);
	fBsp.ReadInt32(iCount);

	for (int i = 0; i < iCount && i < 64; i++)
	{
		int iId, iFlagsVersion, iLumpOffset, iLumpLength;

		fBsp.Seek(iOffset + 4 + i * 16, SEEK_SET);
		fBsp.ReadInt32(iId);
		fBsp.ReadInt32(iFlagsVersion);
		fBsp.ReadInt32(iLumpOffset);
		fBsp.ReadInt32(iLumpLength);

		if (iId != GAMELUMP_STATIC_PROPS || iLumpOffset <= 0)
		{
			continue;
		}

		int iNames;

		fBsp.Seek(iLumpOffset, SEEK_SET);
		fBsp.ReadInt32(iNames);

		for (int n = 0; n < iNames && n < 4096; n++)
		{
			fBsp.Seek(iLumpOffset + 4 + n * 128, SEEK_SET);
			fBsp.ReadString(sModel, sizeof(sModel), -1);

			if (sModel[0] != '\0')
			{
				AddModel(sModel);
			}
		}

		break;
	}
}

//"key" "value" (quotes optional). False for lines that aren't one.
bool SplitKeyValue(const char[] sLine, char[] sKey, int iKeyLength, char[] sValue, int iValueLength)
{
	char sParts[2][PLATFORM_MAX_PATH];
	char sCopy[512];

	strcopy(sCopy, sizeof(sCopy), sLine);
	TrimString(sCopy);

	int iTokens = 0, iPos = 0, iLength = strlen(sCopy);

	while (iTokens < 2 && iPos < iLength)
	{
		while (iPos < iLength && IsCharSpace(sCopy[iPos]))
		{
			iPos++;
		}

		if (iPos >= iLength || (sCopy[iPos] == '/' && sCopy[iPos + 1] == '/'))
		{
			break;
		}

		int iOut = 0;

		if (sCopy[iPos] == '"')
		{
			iPos++;

			while (iPos < iLength && sCopy[iPos] != '"' && iOut < sizeof(sParts[]) - 1)
			{
				sParts[iTokens][iOut++] = sCopy[iPos++];
			}

			iPos++;
		} else {
			while (iPos < iLength && !IsCharSpace(sCopy[iPos]) && iOut < sizeof(sParts[]) - 1)
			{
				sParts[iTokens][iOut++] = sCopy[iPos++];
			}
		}

		sParts[iTokens][iOut] = '\0';
		iTokens++;
	}

	if (iTokens < 2)
	{
		return false;
	}

	strcopy(sKey, iKeyLength, sParts[0]);
	strcopy(sValue, iValueLength, sParts[1]);

	return true;
}

//Lower case, / for folders: how the game asks for files, and how they must be named on a Linux server.
void CleanPath(char[] sPath, int iLength)
{
	ReplaceString(sPath, iLength, "\\", "/");

	for (int i = 0; sPath[i] != '\0'; i++)
	{
		sPath[i] = CharToLower(sPath[i]);
	}

	while (sPath[0] == '/')
	{
		strcopy(sPath, iLength, sPath[1]);
	}
}

bool FirstTime(const char[] sPath)
{
	int iValue;

	if (g_smSeen.GetValue(sPath, iValue))
	{
		return false;
	}

	g_smSeen.SetValue(sPath, 1);

	return true;
}

//A file the map needs. Sent if the server has it loose; nothing to do if it's stock (in the game's VPKs, or packed in
//the map); otherwise it's missing.
bool NeedFile(const char[] sPath, bool bOptional = false)
{
	if (FileExists(sPath, false))
	{
		AddFileToDownloadsTable(sPath);
		g_iAdded++;

		return true;
	}

	if (!FileExists(sPath, true) && !bOptional)
	{
		g_alMissing.PushString(sPath);
	}

	return false;
}

void AddMaterial(const char[] sName, bool bOptional = false)
{
	char sPath[PLATFORM_MAX_PATH];

	FormatEx(sPath, sizeof(sPath), "materials/%s", sName);
	CleanPath(sPath, sizeof(sPath));

	if (StrContains(sPath, ".vmt") == -1)
	{
		StrCat(sPath, sizeof(sPath), ".vmt");
	}

	if (!FirstTime(sPath))
	{
		return;
	}

	// A material packed inside the map (cubemapped "maps/<map>/..." ones) isn't sent, but what it points to may be.
	if (FileExists(sPath, false))
	{
		AddFileToDownloadsTable(sPath);
		g_iAdded++;
		ReadMaterial(sPath, false);
	} else if (FileExists(sPath, true))
	{
		ReadMaterial(sPath, true);
	} else if (!bOptional && StrContains(sPath, "materials/maps/") != 0)
	{
		g_alMissing.PushString(sPath);
	}
}

//The textures a material uses, and the material a "patch" material includes.
void ReadMaterial(const char[] sPath, bool bValveFS)
{
	static const char sTextureKeys[][] =
	{
		"$basetexture", "$basetexture2", "$bumpmap", "$bumpmap2", "$detail", "$envmapmask", "$blendmodulatetexture",
		"$normalmap", "$selfillummask", "$phongexponenttexture", "$lightwarptexture", "$iris", "$corneatexture", "$ambientoccltexture",
		"$texture2", "$dudvmap", "$refracttexture", "$basenormalmap", "$basenormalmap2", "$envmap"
	};
	char sLine[512], sKey[64], sValue[PLATFORM_MAX_PATH], sTexture[PLATFORM_MAX_PATH];

	File fVmt = OpenFile(sPath, "r", bValveFS);

	if (fVmt == null)
	{
		return;
	}

	while (!fVmt.EndOfFile() && fVmt.ReadLine(sLine, sizeof(sLine)))
	{
		if (!SplitKeyValue(sLine, sKey, sizeof(sKey), sValue, sizeof(sValue)) || sValue[0] == '\0')
		{
			continue;
		}

		if (StrEqual(sKey, "include", false))
		{
			ReplaceString(sValue, sizeof(sValue), "\\", "/");

			if (StrContains(sValue, "materials/", false) == 0)
			{
				AddMaterial(sValue[10]);
			} else {
				AddMaterial(sValue);
			}

			continue;
		}

		for (int i = 0; i < sizeof(sTextureKeys); i++)
		{
			if (!StrEqual(sKey, sTextureKeys[i], false))
			{
				continue;
			}

			// The map's own cubemap and the engine's special textures aren't files to send.
			if (StrEqual(sValue, "env_cubemap", false) || sValue[0] == '_')
			{
				break;
			}

			FormatEx(sTexture, sizeof(sTexture), "materials/%s", sValue);
			CleanPath(sTexture, sizeof(sTexture));

			if (StrContains(sTexture, ".vtf") == -1)
			{
				StrCat(sTexture, sizeof(sTexture), ".vtf");
			}

			if (FirstTime(sTexture))
			{
				NeedFile(sTexture);
			}

			break;
		}
	}

	delete fVmt;
}

void AddModel(const char[] sModel)
{
	static const char sExtensions[][] = { ".vvd", ".phy", ".dx80.vtx", ".dx90.vtx", ".sw.vtx", ".vtx" };
	char sPath[PLATFORM_MAX_PATH], sBase[PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH];

	strcopy(sPath, sizeof(sPath), sModel);
	CleanPath(sPath, sizeof(sPath));

	if (!FirstTime(sPath))
	{
		return;
	}

	if (!NeedFile(sPath))
	{
		return; // stock, or missing (then listed)
	}

	strcopy(sBase, sizeof(sBase), sPath);
	sBase[strlen(sBase) - 4] = '\0';

	for (int i = 0; i < sizeof(sExtensions); i++)
	{
		FormatEx(sFile, sizeof(sFile), "%s%s", sBase, sExtensions[i]);

		if (FileExists(sFile, false))
		{
			AddFileToDownloadsTable(sFile);
			g_iAdded++;
		}
	}

	ReadModelTextures(sPath);
}

//A model's textures: every name in its texture list is looked for in each of its texture folders (cdmaterials).
void ReadModelTextures(const char[] sPath)
{
	char sTextures[64][PLATFORM_MAX_PATH], sFolders[16][PLATFORM_MAX_PATH], sMaterial[PLATFORM_MAX_PATH], sCheck[PLATFORM_MAX_PATH];

	File fMdl = OpenFile(sPath, "rb", false);

	if (fMdl == null)
	{
		return;
	}

	int iNumTextures = ReadIntAt(fMdl, 204), iTextureIndex = ReadIntAt(fMdl, 208);
	int iNumFolders = ReadIntAt(fMdl, 212), iFolderIndex = ReadIntAt(fMdl, 216);

	if (iNumTextures < 0 || iNumTextures > sizeof(sTextures))
	{
		iNumTextures = 0;
	}

	if (iNumFolders < 0 || iNumFolders > sizeof(sFolders))
	{
		iNumFolders = 0;
	}

	// mstudiotexture_t is 64 bytes; its first int is where its name is, from the start of that texture.
	for (int i = 0; i < iNumTextures; i++)
	{
		int iTexture = iTextureIndex + i * 64;

		ReadStringAt(fMdl, iTexture + ReadIntAt(fMdl, iTexture), sTextures[i], sizeof(sTextures[]));
	}

	// The folders are a list of ints, each where a folder name is from the start of the file.
	for (int i = 0; i < iNumFolders; i++)
	{
		ReadStringAt(fMdl, ReadIntAt(fMdl, iFolderIndex + i * 4), sFolders[i], sizeof(sFolders[]));
		ReplaceString(sFolders[i], sizeof(sFolders[]), "\\", "/");
	}

	delete fMdl;

	for (int t = 0; t < iNumTextures; t++)
	{
		if (sTextures[t][0] == '\0')
		{
			continue;
		}

		// The first folder that has it is the one the game uses.
		for (int f = 0; f < iNumFolders; f++)
		{
			FormatEx(sMaterial, sizeof(sMaterial), "%s%s%s", sFolders[f], (sFolders[f][0] != '\0' && sFolders[f][strlen(sFolders[f]) - 1] != '/') ? "/" : "", sTextures[t]);
			FormatEx(sCheck, sizeof(sCheck), "materials/%s.vmt", sMaterial);
			CleanPath(sCheck, sizeof(sCheck));

			if (FileExists(sCheck, true))
			{
				AddMaterial(sMaterial);
				break;
			}

			if (f == iNumFolders - 1)
			{
				AddMaterial(sMaterial); // in none of them: listed as missing
			}
		}
	}
}

int ReadIntAt(File fFile, int iOffset)
{
	int iValue;

	if (iOffset < 0 || !fFile.Seek(iOffset, SEEK_SET) || !fFile.ReadInt32(iValue))
	{
		return 0;
	}

	return iValue;
}

void ReadStringAt(File fFile, int iOffset, char[] sBuffer, int iMaxLength)
{
	sBuffer[0] = '\0';

	if (iOffset > 0 && fFile.Seek(iOffset, SEEK_SET))
	{
		fFile.ReadString(sBuffer, iMaxLength, -1);
	}
}

//What the map needs that the server doesn't have, for an admin to copy over (or fetch from FastDL with
//tools/fetch_missing_downloads.sh in the celmod repo).
void WriteMissing(const char[] sMap)
{
	char sDir[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sDir, sizeof(sDir), "data/celmod/missing_downloads");
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/missing_downloads/%s.txt", sMap);

	if (g_alMissing.Length < 1)
	{
		if (FileExists(sPath))
		{
			DeleteFile(sPath);
		}

		return;
	}

	if (!DirExists(sDir))
	{
		CreateDirectory(sDir, 511);
	}

	File fOut = OpenFile(sPath, "w");

	if (fOut == null)
	{
		return;
	}

	fOut.WriteLine("// Files %s needs that aren't on the server (so players can't download them). Copy them into the", sMap);
	fOut.WriteLine("// game folder (hl2mp), named exactly like this, all lower case. Rewritten every time the map loads.");

	for (int i = 0; i < g_alMissing.Length; i++)
	{
		g_alMissing.GetString(i, sFile, sizeof(sFile));
		fOut.WriteLine("%s", sFile);
	}

	delete fOut;

	LogMessage("|CelMod| Map downloads: %d files %s needs aren't on the server, listed in %s.", g_alMissing.Length, sMap, sPath);
}
