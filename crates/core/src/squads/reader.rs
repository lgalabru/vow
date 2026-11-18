use super::{ACCOUNT_BYTES_MAX, discriminator};
use solana_pubkey::Pubkey;

pub(super) struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}
impl<'a> Reader<'a> {
    pub fn new(bytes: &'a [u8]) -> Result<Self, String> {
        if bytes.len() > ACCOUNT_BYTES_MAX {
            return Err("Squads account exceeds the 64 KB inspection limit.".into());
        }
        Ok(Self { bytes, offset: 0 })
    }
    pub fn account(bytes: &'a [u8], name: &str) -> Result<Self, String> {
        let mut r = Self::new(bytes)?;
        if r.take(8)? != discriminator(name) {
            return Err(format!("This is not a Squads {name} account."));
        }
        Ok(r)
    }
    pub fn take(&mut self, count: usize) -> Result<&'a [u8], String> {
        let end = self
            .offset
            .checked_add(count)
            .ok_or("Invalid Squads account size.")?;
        let value = self
            .bytes
            .get(self.offset..end)
            .ok_or("Truncated Squads account data.")?;
        self.offset = end;
        debug_assert!(self.offset <= self.bytes.len());
        Ok(value)
    }
    pub fn u8(&mut self) -> Result<u8, String> {
        Ok(self.take(1)?[0])
    }
    pub fn u16(&mut self) -> Result<u16, String> {
        Ok(u16::from_le_bytes(
            self.take(2)?.try_into().expect("two bytes"),
        ))
    }
    pub fn u32(&mut self) -> Result<u32, String> {
        Ok(u32::from_le_bytes(
            self.take(4)?.try_into().expect("four bytes"),
        ))
    }
    pub fn u64(&mut self) -> Result<u64, String> {
        Ok(u64::from_le_bytes(
            self.take(8)?.try_into().expect("eight bytes"),
        ))
    }
    pub fn i64(&mut self) -> Result<i64, String> {
        Ok(i64::from_le_bytes(
            self.take(8)?.try_into().expect("eight bytes"),
        ))
    }
    pub fn key(&mut self) -> Result<String, String> {
        Ok(Pubkey::new_from_array(self.take(32)?.try_into().expect("32 bytes")).to_string())
    }
    pub fn option_key(&mut self) -> Result<Option<String>, String> {
        match self.u8()? {
            0 => Ok(None),
            1 => Ok(Some(self.key()?)),
            _ => Err("Invalid Squads optional address.".into()),
        }
    }
    pub fn count(&mut self, maximum: usize) -> Result<usize, String> {
        let count = usize::try_from(self.u32()?).map_err(|_| "Invalid Squads vector size.")?;
        if count > maximum {
            return Err(format!(
                "Squads account exceeds the {maximum}-item inspection limit."
            ));
        }
        Ok(count)
    }
    pub fn keys(&mut self, maximum: usize) -> Result<Vec<String>, String> {
        let count = self.count(maximum)?;
        (0..count).map(|_| self.key()).collect()
    }
    pub fn vector(&mut self, maximum: usize) -> Result<Vec<u8>, String> {
        let count = self.count(maximum)?;
        Ok(self.take(count)?.to_vec())
    }
    pub fn permissions(&mut self) -> Result<u8, String> {
        let p = self.u8()?;
        if p & !7 != 0 {
            return Err("Unsupported Squads member permissions.".into());
        }
        Ok(p)
    }
}
